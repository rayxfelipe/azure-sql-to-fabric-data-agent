[CmdletBinding()]
param(
    [string]$TenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb',
    [string]$WorkspaceName = 'ws-e2e-sql-to-fabricagent',
    [string]$WarehouseSqlEndpoint,
    [switch]$UpdateExisting
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Fabric-Helpers.ps1')
$sessionDirectory = Join-Path $PSScriptRoot '..\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0'
if (-not $WarehouseSqlEndpoint) {
    $statePath = Join-Path $sessionDirectory 'fabric-deployment.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw 'Pass -WarehouseSqlEndpoint or deploy the Fabric baseline first.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $WarehouseSqlEndpoint = $state.warehouseSqlEndpoint
}
if ([string]::IsNullOrWhiteSpace($WarehouseSqlEndpoint)) { throw 'The Warehouse SQL endpoint is missing.' }
Connect-Fabric -TenantId $TenantId
$workspace = Get-FabricCollection -Path 'workspaces' |
    Where-Object displayName -eq $WorkspaceName | Select-Object -First 1
if (-not $workspace) { throw "Workspace '$WorkspaceName' is not accessible in the selected tenant." }

& py -3.12 (Join-Path $PSScriptRoot 'Invoke-SqlWithAccessToken.py') `
    --server $WarehouseSqlEndpoint --database 'CommunityHealthAnalyticsWH' --tenant-id $TenantId `
    (Join-Path $PSScriptRoot '..\fabric\warehouse\004_validate_analytics.sql')
if ($LASTEXITCODE -ne 0) { throw 'The reporting baseline must pass validation before creating a grounded ontology.' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\fabric\ontology')).Path
$prior = Get-WorkspaceItem -WorkspaceId $workspace.id -Collection 'ontologies' -DisplayName 'CCSF_Community_Health_Demo_Ontology'
$item = New-DefinitionItem -WorkspaceId $workspace.id -Collection 'ontologies' `
    -DisplayName 'CCSF_Community_Health_Demo_Ontology' `
    -Description 'Five governed entities bound to the reporting schema, with no person-level source.' `
    -Parts @(Get-DefinitionParts -Root $root -Replacements @{ '{{WAREHOUSE_SQL_ENDPOINT}}' = $WarehouseSqlEndpoint }) `
    -PreserveExisting:(-not $UpdateExisting)
$definition = Invoke-Fabric -Method POST -Path "workspaces/$($workspace.id)/ontologies/$($item.id)/getDefinition"
if (-not $definition.definition.parts) { throw 'Ontology creation returned no readable definition.' }
$result = [ordered]@{
    workspaceId = $workspace.id
    ontologyId = $item.id
    displayName = $item.displayName
    returnedDefinitionParts = @($definition.definition.parts).Count
    definitionAction = $(if ($prior) { if ($UpdateExisting) { 'Updated' } else { 'Preserved' } } else { 'Created' })
    bindingStatus = 'Definition retrieved; validate property bindings, refresh, and agent answers in the portal.'
    existingBindingsPolicy = 'Existing definitions are preserved unless -UpdateExisting is explicitly supplied.'
    checkedAt = [DateTimeOffset]::Now.ToString('o')
}
New-Item -ItemType Directory -Path $sessionDirectory -Force | Out-Null
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDirectory 'ontology-deployment.json') -Encoding utf8
$result | ConvertTo-Json
