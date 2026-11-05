#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$WorkspaceId,
    [Parameter(Mandatory)][guid]$DataAgentId,
    [guid]$TenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb',
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Question,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 120,
    [string]$OutputFile
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Question)) { throw 'Question must not be blank.' }
if ($OutputFile) {
    $parent = Split-Path -Path $OutputFile -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Output directory does not exist: $parent"
    }
}
. (Join-Path $PSScriptRoot 'Fabric-Helpers.ps1')
Connect-Fabric -TenantId $TenantId
$script:FabricHttpClient.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$script:McpCancellation = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSeconds))
$uri = "https://api.fabric.microsoft.com/v1/mcp/workspaces/$WorkspaceId/dataagents/$DataAgentId/agent"
$script:SessionId = $null
$script:ProtocolVersion = $null

function Send-Mcp {
    param([hashtable]$Message, [switch]$Notification)
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $uri)
    $request.Version = [Version]'1.1'
    $request.Headers.Accept.ParseAdd('application/json')
    $request.Headers.Accept.ParseAdd('text/event-stream')
    if ($script:SessionId) { [void]$request.Headers.TryAddWithoutValidation('Mcp-Session-Id', $script:SessionId) }
    if ($script:ProtocolVersion) { [void]$request.Headers.TryAddWithoutValidation('MCP-Protocol-Version', $script:ProtocolVersion) }
    $request.Content = [Net.Http.StringContent]::new(($Message | ConvertTo-Json -Depth 30 -Compress), [Text.Encoding]::UTF8, 'application/json')
    $response = $null
    try {
        $response = $script:FabricHttpClient.SendAsync($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $script:McpCancellation.Token).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $errorBody = $response.Content.ReadAsStringAsync($script:McpCancellation.Token).GetAwaiter().GetResult()
            throw "MCP $($Message.method) failed with HTTP $([int]$response.StatusCode): $errorBody"
        }
        if ($response.Headers.Contains('Mcp-Session-Id')) { $script:SessionId = @($response.Headers.GetValues('Mcp-Session-Id'))[0] }
        if ($Notification) { return }
        if ($response.Content.Headers.ContentType.MediaType -eq 'application/json') {
            $reply = $response.Content.ReadAsStringAsync($script:McpCancellation.Token).GetAwaiter().GetResult() | ConvertFrom-Json
            if ($reply.error) { throw "MCP error: $($reply.error | ConvertTo-Json -Compress)" }
            if ($reply.id -ne $Message.id) { throw 'MCP response ID did not match the request.' }
            return $reply.result
        }
        if ($response.Content.Headers.ContentType.MediaType -ne 'text/event-stream') { throw 'Unexpected MCP response content type.' }
        $stream = $response.Content.ReadAsStreamAsync($script:McpCancellation.Token).GetAwaiter().GetResult()
        $reader = [IO.StreamReader]::new($stream)
        try {
            $data = [Collections.Generic.List[string]]::new()
            while ($true) {
                $line = $reader.ReadLineAsync($script:McpCancellation.Token).AsTask().GetAwaiter().GetResult()
                if ($null -eq $line) { break }
                if ($line.StartsWith('data:')) { $data.Add($line.Substring(5).TrimStart()) }
                elseif ($line -eq '' -and $data.Count -gt 0) {
                    $reply = ($data -join "`n") | ConvertFrom-Json
                    $data.Clear()
                    if ($reply.id -eq $Message.id) {
                        if ($reply.error) { throw "MCP error: $($reply.error | ConvertTo-Json -Compress)" }
                        return $reply.result
                    }
                }
            }
            throw 'MCP stream ended without a matching response.'
        }
        finally { $reader.Dispose() }
    }
    finally {
        if ($response) { $response.Dispose() }
        $request.Dispose()
    }
}

$timer = [Diagnostics.Stopwatch]::StartNew()
$record = [ordered]@{
    workspaceId = $WorkspaceId.ToString()
    dataAgentId = $DataAgentId.ToString()
    question = $Question
    transport = 'native-dotnet-mcp'
    status = 'Failed'
    isError = $true
}
try {
    $initial = Send-Mcp @{jsonrpc='2.0';id=1;method='initialize';params=@{protocolVersion='2025-11-25';capabilities=@{};clientInfo=@{name='ccsf-demo-verifier';version='1.0.0'}}}
    if (-not $initial.protocolVersion) { throw 'The MCP server did not negotiate a protocol version.' }
    $script:ProtocolVersion = $initial.protocolVersion
    Send-Mcp @{jsonrpc='2.0';method='notifications/initialized'} -Notification
    $toolResult = Send-Mcp @{jsonrpc='2.0';id=2;method='tools/list'}
    if ($null -eq $toolResult.tools -or @($toolResult.tools).Count -ne 1) { throw 'Expected exactly one Fabric data-agent tool.' }
    $tool = $toolResult.tools[0]
    $properties = @($tool.inputSchema.properties.PSObject.Properties)
    if ($properties.Count -ne 1 -or $properties[0].Value.type -ne 'string') { throw 'Unexpected agent question schema.' }
    $arguments = @{}
    $arguments[$properties[0].Name] = $Question
    $answer = Send-Mcp @{jsonrpc='2.0';id=3;method='tools/call';params=@{name=$tool.name;arguments=$arguments}}
    $text = (@($answer.content | Where-Object type -eq text | ForEach-Object text) -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Agent returned no text answer.' }
    $record.tool = $tool.name
    $record.answer = $text
    if ($answer.isError) { throw "Agent runtime error: $text" }
    $record.status = 'Completed'
    $record.isError = $false
}
finally {
    $timer.Stop()
    $record.checkedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $record.elapsedSeconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
    if ($script:SessionId) {
        $close = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Delete, $uri)
        [void]$close.Headers.TryAddWithoutValidation('Mcp-Session-Id', $script:SessionId)
        [void]$close.Headers.TryAddWithoutValidation('MCP-Protocol-Version', $script:ProtocolVersion)
        $closeTimeout = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(5))
        $closed = $null
        try {
            $closed = $script:FabricHttpClient.SendAsync($close, $closeTimeout.Token).GetAwaiter().GetResult()
            if (-not $closed.IsSuccessStatusCode -and [int]$closed.StatusCode -notin @(404, 405)) {
                Write-Warning "MCP session cleanup returned HTTP $([int]$closed.StatusCode)."
            }
        }
        catch [Net.Http.HttpRequestException], [OperationCanceledException] {
            Write-Warning "MCP session cleanup failed: $($_.Exception.Message)"
        }
        finally {
            if ($closed) { $closed.Dispose() }
            $close.Dispose()
            $closeTimeout.Dispose()
        }
    }
    $script:McpCancellation.Dispose()
    $script:FabricHttpClient.Dispose()
    if ($OutputFile) { $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputFile -Encoding utf8 }
}
$record | ConvertTo-Json -Depth 20
