$FabricBaseUri = 'https://api.fabric.microsoft.com/v1'

function Resolve-FabricUri {
    param([Parameter(Mandatory)][string]$Path)
    $uri = $null
    if ([uri]::TryCreate($Path, [UriKind]::Absolute, [ref]$uri)) {
        $allowedHost = $uri.Host -eq 'api.fabric.microsoft.com' -or $uri.Host -match '^wabi-[a-z0-9-]+\.analysis\.windows\.net$'
        if ($uri.Scheme -ne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or -not $allowedHost) {
            throw "Refusing to send a Fabric token to an unexpected endpoint: $($uri.Host)."
        }
        return $uri.AbsoluteUri
    }
    if ($Path.StartsWith('//')) { throw 'Protocol-relative Fabric endpoints are not allowed.' }
    return "$FabricBaseUri/$($Path.TrimStart('/'))"
}

function Get-TenantAccessToken {
    param(
        [Parameter(Mandatory)][guid]$TenantId,
        [ValidateSet('https://api.fabric.microsoft.com', 'https://analysis.windows.net/powerbi/api')]
        [string]$Resource = 'https://api.fabric.microsoft.com'
    )
    $azureCli = (Get-Command az -ErrorAction Stop).Source
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/d /s /c ""{0}" account get-access-token --tenant "{1}" --resource "{2}" --query accessToken --output tsv"' -f $azureCli, $TenantId, $Resource
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Fabric token acquisition timed out after 60 seconds. Sign in with az login --tenant $TenantId, then retry."
        }
        $token = $stdout.GetAwaiter().GetResult().Trim()
        $authError = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
            throw "Unable to acquire a Fabric token. Sign in with az login --tenant $TenantId. $authError"
        }
    }
    finally {
        $process.Dispose()
    }
    return $token
}

function Connect-Fabric {
    param([Parameter(Mandatory)][guid]$TenantId)
    $token = Get-TenantAccessToken -TenantId $TenantId
    $script:FabricHttpClient = [Net.Http.HttpClient]::new()
    $script:FabricHttpClient.Timeout = [TimeSpan]::FromSeconds(90)
    $script:FabricHttpClient.DefaultRequestVersion = [Version]'1.1'
    $script:FabricHttpClient.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
}

function ConvertTo-InlinePart {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    @{
        path = $Path
        payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
        payloadType = 'InlineBase64'
    }
}

function Invoke-Fabric {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [switch]$IncludeResponse
    )
    $uri = Resolve-FabricUri -Path $Path
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $uri)
        $request.Version = [Version]'1.1'
        if ($null -ne $Body) {
            $request.Content = [Net.Http.StringContent]::new(
                ($Body | ConvertTo-Json -Depth 100 -Compress), [Text.Encoding]::UTF8, 'application/json'
            )
        }
        $httpResponse = $null
        $retryAfter = 5
        try {
            $httpResponse = $script:FabricHttpClient.SendAsync($request).GetAwaiter().GetResult()
            $statusCode = [int]$httpResponse.StatusCode
            $content = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $contentType = [string]$httpResponse.Content.Headers.ContentType.MediaType
            $location = [string]$httpResponse.Headers.Location
            if ($httpResponse.Headers.RetryAfter.Delta) {
                $retryAfter = [Math]::Max(1, [int]$httpResponse.Headers.RetryAfter.Delta.TotalSeconds)
            }
        }
        catch {
            $transportError = $_.Exception
            while ($transportError.InnerException -and
                $transportError -isnot [Net.Http.HttpRequestException] -and
                $transportError -isnot [Threading.Tasks.TaskCanceledException]) {
                $transportError = $transportError.InnerException
            }
            if ($Method -eq 'GET' -and $attempt -lt 4 -and
                ($transportError -is [Net.Http.HttpRequestException] -or
                 $transportError -is [Threading.Tasks.TaskCanceledException])) {
                Write-Warning "Transient Fabric GET failure; retry $attempt of 3: $($transportError.Message)"
                Start-Sleep -Seconds $retryAfter
                continue
            }
            throw
        }
        finally {
            if ($httpResponse) { $httpResponse.Dispose() }
            $request.Dispose()
        }
        if (($statusCode -eq 429 -or ($Method -eq 'GET' -and $statusCode -in @(502, 503, 504))) -and $attempt -lt 4) {
            Start-Sleep -Seconds $retryAfter
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($content) -and $contentType -and $contentType -notmatch '[/+]json$') {
            throw "Fabric API $Method $Path returned non-JSON content ($contentType) with HTTP $statusCode. Verify the endpoint and authentication."
        }
        $bodyValue = if ([string]::IsNullOrWhiteSpace($content)) { $null } else { $content | ConvertFrom-Json }
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            throw "Fabric API $Method $Path failed with HTTP $statusCode`: $($bodyValue | ConvertTo-Json -Depth 20 -Compress)"
        }
        if ($IncludeResponse) {
            return [pscustomobject]@{ Body = $bodyValue; Location = $location; RetryAfter = $retryAfter; StatusCode = $statusCode }
        }
        if ($statusCode -eq 202) {
            if (-not $location) { throw "Fabric accepted $Path without an operation Location header." }
            return Wait-FabricOperation -Location $location -RetryAfter $retryAfter
        }
        return $bodyValue
    }
}

function Wait-FabricOperation {
    param([Parameter(Mandatory)][string]$Location, [int]$RetryAfter = 5)
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Seconds $RetryAfter
        $response = Invoke-Fabric -Method GET -Path $Location -IncludeResponse
        $operation = $response.Body
        if ($operation.status -eq 'Succeeded') {
            if ($response.Location -and $response.Location.TrimEnd('/') -ne $Location.TrimEnd('/')) {
                return Invoke-Fabric -Method GET -Path $response.Location
            }
            return $operation
        }
        if ($operation.status -in @('Failed', 'Cancelled')) {
            throw "Fabric operation failed: $($operation | ConvertTo-Json -Depth 20 -Compress)"
        }
        $RetryAfter = $response.RetryAfter
    }
    throw "Fabric operation timed out: $Location"
}

function Get-FabricCollection {
    param([Parameter(Mandatory)][string]$Path)
    $values = @()
    do {
        $page = Invoke-Fabric -Method GET -Path $Path
        $values += @($page.value)
        $Path = $page.continuationUri
    } while ($Path)
    return $values
}

function Get-WorkspaceItem {
    param([string]$WorkspaceId, [string]$Collection, [string]$DisplayName)
    Get-FabricCollection -Path "workspaces/$WorkspaceId/$Collection" |
        Where-Object displayName -eq $DisplayName | Select-Object -First 1
}

function New-DefinitionItem {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$Collection,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][object[]]$Parts,
        [string]$Description,
        [switch]$PreserveExisting
    )
    $existing = Get-WorkspaceItem -WorkspaceId $WorkspaceId -Collection $Collection -DisplayName $DisplayName
    if ($existing) {
        if (-not $PreserveExisting -and $Collection -ne 'mirroredDatabases') {
            if ($Collection -eq 'dataAgents') {
                $prior = Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/$Collection/$($existing.id)/getDefinition"
                $Parts = @($Parts) + @($prior.definition.parts | Where-Object {
                    $_.path -like 'Files/Config/published/*' -or $_.path -eq 'Files/Config/publish_info.json'
                })
            }
            Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/$Collection/$($existing.id)/updateDefinition" -Body @{
                definition = @{ parts = $Parts }
            } | Out-Null
        }
        return $existing
    }
    $item = Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/$Collection" -Body @{
        displayName = $DisplayName
        description = $Description
        definition = @{ parts = $Parts }
    }
    if (-not $item.id) { throw "Fabric created $Collection without returning a resource ID." }
    return $item
}

function Publish-FabricDataAgent {
    param([Parameter(Mandatory)][guid]$WorkspaceId, [Parameter(Mandatory)][guid]$DataAgentId)
    $path = "workspaces/$WorkspaceId/dataAgents/$DataAgentId"
    Invoke-Fabric -Method POST -Path "$path/staging/publish" -Body @{
        publishedDescription = 'Synthetic community-health demonstration over governed reporting data.'
    } | Out-Null
    $definition = Invoke-Fabric -Method POST -Path "$path/getDefinition"
    $paths = @($definition.definition.parts.path)
    if ('Files/Config/published/stage_config.json' -notin $paths -or
        -not ($paths | Where-Object { $_ -like 'Files/Config/published/*/datasource.json' })) {
        throw 'Data Agent publication did not persist its published instructions and data source.'
    }
}

function Start-FabricSemanticModelRefresh {
    param(
        [Parameter(Mandatory)][guid]$TenantId,
        [Parameter(Mandatory)][guid]$WorkspaceId,
        [Parameter(Mandatory)][guid]$SemanticModelId
    )
    $token = Get-TenantAccessToken -TenantId $TenantId -Resource 'https://analysis.windows.net/powerbi/api'
    $headers = @{ Authorization = "Bearer $token" }
    $path = "https://api.powerbi.com/v1.0/myorg/groups/$WorkspaceId/datasets/$SemanticModelId/refreshes"
    $response = Invoke-WebRequest -Method POST -Uri $path -Headers $headers `
        -ContentType 'application/json' -Body '{"type":"full"}' -TimeoutSec 60
    $location = [string]$response.Headers.Location
    $jobUri = $null
    $expectedPath = ([uri]$path).AbsolutePath + '/'
    if (-not [uri]::TryCreate($location, [UriKind]::Absolute, [ref]$jobUri) -or
        $jobUri.Scheme -ne 'https' -or $jobUri.Port -ne 443 -or $jobUri.UserInfo -or
        ($jobUri.Host -ne 'api.powerbi.com' -and $jobUri.Host -notmatch '^wabi-[a-z0-9-]+\.analysis\.windows\.net$') -or
        -not $jobUri.AbsolutePath.StartsWith($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Semantic-model refresh did not return a trusted job Location.'
    }
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $refresh = Invoke-RestMethod -Method GET -Uri $location -Headers $headers -TimeoutSec 60
        if ($refresh.status -eq 'Completed') { return $refresh }
        if ($refresh.status -in @('Failed', 'Cancelled', 'Disabled')) {
            throw "Semantic-model refresh failed: $($refresh | ConvertTo-Json -Depth 20 -Compress)"
        }
        Start-Sleep -Seconds 5
    }
    throw "Semantic-model refresh did not complete before timeout: $location"
}

function Start-FabricPipeline {
    param([Parameter(Mandatory)][string]$WorkspaceId, [Parameter(Mandatory)][string]$PipelineId)
    $response = Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/items/$PipelineId/jobs/instances?jobType=Pipeline" -IncludeResponse
    if (-not $response.Location) { throw 'Pipeline start did not return its job-instance Location.' }
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $job = Invoke-Fabric -Method GET -Path $response.Location
        if ($job.status -eq 'Completed') { return $job }
        if ($job.status -in @('Failed', 'Cancelled', 'Deduped')) {
            throw "Pipeline ended in state '$($job.status)': $($job.failureReason | ConvertTo-Json -Depth 20 -Compress)"
        }
        Start-Sleep -Seconds 10
    }
    throw "Pipeline did not complete before timeout: $($response.Location)"
}

function Start-FabricMirroring {
    param([Parameter(Mandatory)][string]$WorkspaceId, [Parameter(Mandatory)][string]$MirrorId)
    $path = "workspaces/$WorkspaceId/mirroredDatabases/$MirrorId"
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $status = Invoke-Fabric -Method POST -Path "$path/getMirroringStatus"
        switch ($status.status) {
            { $_ -in @('Running', 'Running with warning', 'Started') } { return $status }
            { $_ -in @('Initialized', 'Stopped', 'Paused') } {
                Invoke-Fabric -Method POST -Path "$path/startMirroring" | Out-Null
            }
            { $_ -in @('Initializing', 'Starting', 'Stopping') } { }
            default { throw "Mirroring cannot start: $($status | ConvertTo-Json -Depth 20 -Compress)" }
        }
        Start-Sleep -Seconds 10
    }
    throw "Mirroring did not start before timeout: $($status.status)"
}

function Get-DefinitionParts {
    param([Parameter(Mandatory)][string]$Root, [hashtable]$Replacements = @{})
    Get-ChildItem -LiteralPath $Root -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $content = Get-Content -LiteralPath $_.FullName -Raw
        foreach ($key in $Replacements.Keys) { $content = $content.Replace($key, $Replacements[$key]) }
        if ($content -match '\{\{[A-Z_]+\}\}') { throw "An unresolved placeholder remains in $relative." }
        ConvertTo-InlinePart -Path $relative -Content $content
    }
}
