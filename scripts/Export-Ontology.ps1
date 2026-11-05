[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$WorkspaceId,
    [Parameter(Mandatory)][guid]$OntologyId,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$TenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb',
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Fabric-Helpers.ps1')
Connect-Fabric -TenantId $TenantId
$response = Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/ontologies/$OntologyId/getDefinition"
if (-not $response.definition.parts) { throw 'The ontology returned no definition parts.' }
$root = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\') + '\'
foreach ($part in $response.definition.parts) {
    if ($part.payloadType -ne 'InlineBase64') { throw "Unsupported payload type: $($part.payloadType)" }
    $relative = $part.path.Replace('/', '\')
    if ([IO.Path]::IsPathRooted($relative) -or '..' -in $relative.Split('\')) {
        throw "Unsafe definition path: $($part.path)"
    }
    $target = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Definition path escapes the export directory.' }
    if ((Test-Path -LiteralPath $target) -and -not $Overwrite) { throw "Export target exists; use -Overwrite intentionally: $target" }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    [IO.File]::WriteAllText($target, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload)))
}
Write-Host "Exported $(@($response.definition.parts).Count) ontology definition parts to $root. No rows or credentials were exported."
