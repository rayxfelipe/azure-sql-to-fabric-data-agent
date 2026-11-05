$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Fabric-Helpers.ps1')

function Start-Sleep { param([int]$Seconds) }
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
Assert-True ((Resolve-FabricUri -Path 'workspaces') -eq 'https://api.fabric.microsoft.com/v1/workspaces') 'Relative Fabric path resolution failed.'
Assert-True ((Resolve-FabricUri -Path 'https://wabi-west-us3-a-primary-redirect.analysis.windows.net/operation') -like 'https://wabi-*') 'A legitimate regional Fabric operation endpoint was rejected.'
foreach ($uri in @('https://evil.example/operation', 'https://api.fabric.microsoft.com.evil.example/operation', 'http://api.fabric.microsoft.com/v1', 'https://user@api.fabric.microsoft.com/v1', 'https://wabi-west-us3.analysis.windows.net.evil.example/operation')) {
    $rejected = $false
    try { Resolve-FabricUri -Path $uri | Out-Null }
    catch { $rejected = $_.Exception.Message -like 'Refusing to send a Fabric token*' }
    Assert-True $rejected "An untrusted Fabric endpoint was accepted: $uri"
}

$script:FabricHttpClient = [pscustomobject]@{}
$script:FabricHttpClient | Add-Member -MemberType ScriptMethod -Name SendAsync -Value {
    param($Request)
    $response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$script:NonJsonStatus)
    $response.Content = [Net.Http.StringContent]::new('<html>Unexpected endpoint</html>')
    $response.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('text/html')
    return [Threading.Tasks.Task]::FromResult($response)
}
foreach ($script:NonJsonStatus in @(200, 403)) {
    $failed = $false
    try { Invoke-Fabric -Method GET -Path 'workspaces' | Out-Null }
    catch { $failed = $_.Exception.Message -like "*returned non-JSON content (text/html) with HTTP $script:NonJsonStatus.*" }
    Assert-True $failed "A non-JSON HTTP $script:NonJsonStatus response lost its endpoint/status diagnostic."
}

$validationAst = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Test-Deployment.ps1'), [ref]$null, [ref]$null
)
$fileAssignment = $validationAst.Find({
    param($Node)
    $Node -is [Management.Automation.Language.AssignmentStatementAst] -and
        $Node.Left.Extent.Text -match '\$validationFiles$'
}, $true)
Assert-True ($null -ne $fileAssignment) 'Deployment validation SQL file selection is missing.'
foreach ($restricted in @($false, $true)) {
    & {
        param($Directory, $Statement, $Restricted)
        $CheckRestrictedIdentity = $Restricted
        . ([scriptblock]::Create($Statement.Replace('$PSScriptRoot', '$Directory')))
        Assert-True ($validationFiles -is [string[]] -and $validationFiles.Count -eq 1) 'A single SQL path was unwrapped before native argument splatting.'
        Assert-True ($validationFiles[0].Contains('fabric demo regression') -and $validationFiles[0].EndsWith('.sql')) 'A SQL path with spaces was truncated.'
    } (Join-Path ([IO.Path]::GetTempPath()) 'fabric demo regression\scripts') $fileAssignment.Extent.Text $restricted
}

function Invoke-Fabric {
    param([string]$Method, [string]$Path, [object]$Body, [switch]$IncludeResponse)
    $script:Calls.Add($Path)
    $script:Bodies.Add($Body)
    if ($script:Responses.Count -eq 0) { throw "Unexpected request: $Path" }
    return $script:Responses.Dequeue()
}
function Reset-Mock {
    $script:Calls = [Collections.Generic.List[string]]::new()
    $script:Bodies = [Collections.Generic.List[object]]::new()
    $script:Responses = [Collections.Generic.Queue[object]]::new()
}

Reset-Mock
$script:Responses.Enqueue([pscustomobject]@{
    Body = @{ status = 'Succeeded' }
    Location = 'https://api.fabric.microsoft.com/v1/operations/test/result'
    RetryAfter = 0
})
$script:Responses.Enqueue(@{ id = 'created-item'; displayName = 'Demo' })
$result = Wait-FabricOperation -Location 'https://api.fabric.microsoft.com/v1/operations/test' -RetryAfter 0
Assert-True ($result.id -eq 'created-item') 'LRO did not return the created resource.'
Assert-True ($script:Calls[1].EndsWith('/result')) 'LRO result endpoint was not requested.'

Reset-Mock
$script:Responses.Enqueue([pscustomobject]@{ Body = @{ status = 'Succeeded' }; Location = ''; RetryAfter = 0 })
$result = Wait-FabricOperation -Location 'https://api.fabric.microsoft.com/v1/operations/no-result' -RetryAfter 0
Assert-True ($result.status -eq 'Succeeded' -and $script:Calls.Count -eq 1) 'A no-result operation was handled incorrectly.'

Reset-Mock
$script:Responses.Enqueue([pscustomobject]@{ Body = @{ status = 'Failed'; error = 'Expected test failure' }; RetryAfter = 0 })
$failed = $false
try { Wait-FabricOperation -Location 'https://api.fabric.microsoft.com/v1/operations/failure' -RetryAfter 0 }
catch { $failed = $_.Exception.Message -like 'Fabric operation failed:*' }
Assert-True $failed 'A failed LRO was not surfaced.'

Reset-Mock
$script:Responses.Enqueue(@{ value = @(@{ id = 'first' }); continuationUri = 'https://api.fabric.microsoft.com/v1/next' })
$script:Responses.Enqueue(@{ value = @(@{ id = 'second' }) })
$items = @(Get-FabricCollection -Path 'workspaces')
Assert-True ($items.Count -eq 2 -and $items[1].id -eq 'second') 'Pagination did not return both items.'

Reset-Mock
$script:Responses.Enqueue([pscustomobject]@{ Location = 'https://api.fabric.microsoft.com/v1/jobs/test' })
$script:Responses.Enqueue(@{ status = 'Completed' })
$job = Start-FabricPipeline -WorkspaceId 'workspace' -PipelineId 'pipeline'
Assert-True ($job.status -eq 'Completed') 'Pipeline completion was not observed.'

Reset-Mock
$script:Responses.Enqueue(@{ status = 'Initializing' })
$script:Responses.Enqueue(@{ status = 'Initialized' })
$script:Responses.Enqueue($null)
$script:Responses.Enqueue(@{ status = 'Running' })
$mirror = Start-FabricMirroring -WorkspaceId 'workspace' -MirrorId 'mirror'
Assert-True ($mirror.status -eq 'Running') 'An initializing mirror did not start.'
Assert-True ($script:Calls[1].EndsWith('/getMirroringStatus') -and $script:Calls[2].EndsWith('/startMirroring')) 'Mirroring was started before initialization completed.'

Reset-Mock
$script:Responses.Enqueue(@{ status = 'Paused' })
$script:Responses.Enqueue($null)
$script:Responses.Enqueue(@{ status = 'Running' })
$mirror = Start-FabricMirroring -WorkspaceId 'workspace' -MirrorId 'mirror'
Assert-True ($mirror.status -eq 'Running' -and $script:Calls[1].EndsWith('/startMirroring')) 'A paused mirror was not resumed.'

Reset-Mock
$script:Responses.Enqueue(@{ value = @(@{ id = 'existing'; displayName = 'Demo' }) })
$item = New-DefinitionItem -WorkspaceId 'workspace' -Collection 'ontologies' -DisplayName 'Demo' -Parts @(@{}) -PreserveExisting
Assert-True ($item.id -eq 'existing' -and $script:Calls.Count -eq 1) 'Preserving an ontology unexpectedly updated it.'

Reset-Mock
$script:Responses.Enqueue(@{ value = @(@{ id = 'existing'; displayName = 'Demo' }) })
$script:Responses.Enqueue(@{ definition = @{ parts = @(
    @{ path = 'Files/Config/published/stage_config.json'; payload = 'published' },
    @{ path = 'Files/Config/publish_info.json'; payload = 'info' }
) } })
$script:Responses.Enqueue($null)
New-DefinitionItem -WorkspaceId 'workspace' -Collection 'dataAgents' -DisplayName 'Demo' `
    -Parts @(@{ path = 'Files/Config/draft/stage_config.json'; payload = 'draft' }) | Out-Null
$paths = @($script:Bodies[2].definition.parts.path)
Assert-True ($paths.Count -eq 3 -and 'Files/Config/published/stage_config.json' -in $paths) 'Updating a draft discarded the prior published configuration.'

$workspaceId = '11111111-1111-1111-1111-111111111111'
$agentId = '22222222-2222-2222-2222-222222222222'
$modelId = '33333333-3333-3333-3333-333333333333'
Reset-Mock
$script:Responses.Enqueue($null)
$script:Responses.Enqueue(@{ definition = @{ parts = @(
    @{ path = 'Files/Config/published/stage_config.json' },
    @{ path = 'Files/Config/published/model/datasource.json' }
) } })
Publish-FabricDataAgent -WorkspaceId $workspaceId -DataAgentId $agentId
Assert-True ($script:Calls[0].EndsWith('/staging/publish')) 'Agent publication did not use the documented staging endpoint.'

Reset-Mock
$script:Responses.Enqueue($null)
$script:Responses.Enqueue(@{ definition = @{ parts = @() } })
$failed = $false
try { Publish-FabricDataAgent -WorkspaceId $workspaceId -DataAgentId $agentId }
catch { $failed = $_.Exception.Message -like 'Data Agent publication did not persist*' }
Assert-True $failed 'Publication without published configuration was accepted.'

function Get-TenantAccessToken { param($TenantId, $Resource) return 'test-token' }
function Invoke-WebRequest {
    param($Method, $Uri, $Headers, $ContentType, $Body, $TimeoutSec)
    return @{ Headers = @{ Location = @($script:RefreshLocation) } }
}
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $TimeoutSec)
    return @{ status = $script:RefreshStatus }
}
$script:RefreshLocation = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$modelId/refreshes/job"
$script:RefreshStatus = 'Completed'
$refresh = Start-FabricSemanticModelRefresh -TenantId $workspaceId -WorkspaceId $workspaceId -SemanticModelId $modelId
Assert-True ($refresh.status -eq 'Completed') 'A completed semantic-model refresh was not returned.'
$script:RefreshLocation = "https://wabi-west-us3-a-primary-redirect.analysis.windows.net/v1.0/myorg/groups/$workspaceId/datasets/$modelId/refreshes/job"
$refresh = Start-FabricSemanticModelRefresh -TenantId $workspaceId -WorkspaceId $workspaceId -SemanticModelId $modelId
Assert-True ($refresh.status -eq 'Completed') 'A trusted regional model-refresh job was rejected.'
$script:RefreshStatus = 'Failed'
$failed = $false
try { Start-FabricSemanticModelRefresh -TenantId $workspaceId -WorkspaceId $workspaceId -SemanticModelId $modelId | Out-Null }
catch { $failed = $_.Exception.Message -like 'Semantic-model refresh failed:*' }
Assert-True $failed 'A failed semantic-model refresh was accepted.'
$script:RefreshLocation = 'https://evil.example/refresh'
$failed = $false
try { Start-FabricSemanticModelRefresh -TenantId $workspaceId -WorkspaceId $workspaceId -SemanticModelId $modelId | Out-Null }
catch { $failed = $_.Exception.Message -like 'Semantic-model refresh did not return a trusted*' }
Assert-True $failed 'A refresh Location on an untrusted host was accepted.'
$script:RefreshLocation = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/datasets/$agentId/refreshes/job"
$failed = $false
try { Start-FabricSemanticModelRefresh -TenantId $workspaceId -WorkspaceId $workspaceId -SemanticModelId $modelId | Out-Null }
catch { $failed = $_.Exception.Message -like 'Semantic-model refresh did not return a trusted*' }
Assert-True $failed 'A refresh Location for a different model was accepted.'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\fabric\ontology')).Path
$parts = @(Get-DefinitionParts -Root $root -Replacements @{ '{{WAREHOUSE_SQL_ENDPOINT}}' = 'demo.datawarehouse.fabric.microsoft.com' })
Assert-True ('.platform' -in $parts.path -and 'model.tmdl' -in $parts.path) 'The definition is missing required parts.'
foreach ($part in $parts) {
    $content = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload))
    Assert-True ($content -notmatch '\{\{[A-Z_]+\}\}') "Unresolved placeholder in $($part.path)."
}

$failed = $false
try { Get-DefinitionParts -Root $root -Replacements @{} | Out-Null }
catch { $failed = $_.Exception.Message -like 'An unresolved placeholder remains*' }
Assert-True $failed 'A definition with unresolved placeholders was accepted.'

$mcpAst = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Invoke-FabricDataAgent.ps1'), [ref]$null, [ref]$null
)
$mcpFunction = $mcpAst.Find({
    param($Node)
    $Node -is [Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Send-Mcp'
}, $true)
Set-Item -Path Function:\Send-Mcp -Value $mcpFunction.Body.GetScriptBlock()
$uri = 'https://api.fabric.microsoft.com/v1/mcp/test'
$script:SessionId = $null
$script:ProtocolVersion = $null
$script:McpCancellation = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(10))
$script:FabricHttpClient = [pscustomobject]@{}
$script:FabricHttpClient | Add-Member -MemberType ScriptMethod -Name SendAsync -Value {
    param($Request, $CompletionOption, $CancellationToken)
    $response = [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$script:McpStatus)
    $response.Content = [Net.Http.StringContent]::new($script:McpContent)
    $response.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new($script:McpContentType)
    return [Threading.Tasks.Task]::FromResult($response)
}
$message = @{ jsonrpc = '2.0'; id = 9; method = 'tools/list' }
try {
    $script:McpStatus = 200
    $script:McpContentType = 'application/json'
    $script:McpContent = '{"jsonrpc":"2.0","id":9,"result":{"answer":"checked"}}'
    Assert-True ((Send-Mcp $message).answer -eq 'checked') 'The MCP JSON response was not parsed.'

    $script:McpContentType = 'text/event-stream'
    $script:McpContent = ": keepalive`n`nevent: message`ndata: {`"jsonrpc`":`"2.0`",`"method`":`"notifications/progress`"}`n`nevent: message`ndata: {`"jsonrpc`":`"2.0`",`"id`":9,`ndata: `"result`":{`"answer`":`"checked`"}}`n`n"
    Assert-True ((Send-Mcp $message).answer -eq 'checked') 'MCP SSE parsing lost multiline data or mishandled a notification.'

    $script:McpContentType = 'application/json'
    $script:McpContent = '{"jsonrpc":"2.0","id":9,"error":{"code":-32600,"message":"Expected failure"}}'
    $failed = $false
    try { Send-Mcp $message | Out-Null }
    catch { $failed = $_.Exception.Message -like 'MCP error:*Expected failure*' }
    Assert-True $failed 'An MCP JSON-RPC error was accepted as an answer.'

    $script:McpContent = '{"jsonrpc":"2.0","id":10,"result":{}}'
    $failed = $false
    try { Send-Mcp $message | Out-Null }
    catch { $failed = $_.Exception.Message -eq 'MCP response ID did not match the request.' }
    Assert-True $failed 'An unrelated MCP JSON response was accepted.'

    $script:McpContentType = 'text/event-stream'
    $script:McpContent = ": keepalive`n`n"
    $failed = $false
    try { Send-Mcp $message | Out-Null }
    catch { $failed = $_.Exception.Message -eq 'MCP stream ended without a matching response.' }
    Assert-True $failed 'An empty MCP stream was accepted.'

    $script:McpStatus = 503
    $script:McpContentType = 'text/plain'
    $script:McpContent = 'Expected service failure'
    $failed = $false
    try { Send-Mcp $message | Out-Null }
    catch { $failed = $_.Exception.Message -like 'MCP tools/list failed with HTTP 503:*' }
    Assert-True $failed 'An MCP HTTP failure lost its status diagnostic.'
}
finally { $script:McpCancellation.Dispose() }

Write-Host 'PASS: 29 Fabric helper regression checks (no network calls).'
