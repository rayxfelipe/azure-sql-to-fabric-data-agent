[CmdletBinding()]
param(
    [string]$TenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb',
    [switch]$CheckRestrictedIdentity
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Fabric-Helpers.ps1')
$stateFile = Join-Path $PSScriptRoot '..\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0\fabric-deployment.json'
if (-not (Test-Path -LiteralPath $stateFile)) { throw 'Fabric deployment state is missing.' }
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
Connect-Fabric -TenantId $TenantId
$mirror = Invoke-Fabric -Method POST -Path "workspaces/$($state.workspaceId)/mirroredDatabases/$($state.mirroredDatabaseId)/getMirroringStatus"
if ($mirror.status -notin @('Running', 'Running with warning', 'Started')) {
    throw "Mirroring is not running: $($mirror.status)"
}
if ($mirror.status -eq 'Running with warning') { Write-Warning 'Inspect the mirroring warning before presenting.' }
if (-not $CheckRestrictedIdentity) {
    if (-not $state.analyticsPipelineJobId) {
        throw 'No completed analytics pipeline job is recorded. Run the repaired Fabric deployment first.'
    }
    $pipelineJob = Invoke-Fabric -Method GET -Path "workspaces/$($state.workspaceId)/items/$($state.pipelineId)/jobs/instances/$($state.analyticsPipelineJobId)"
    if ($pipelineJob.status -ne 'Completed') {
        throw "Recorded analytics refresh did not complete successfully: $($pipelineJob.status)"
    }
}
foreach ($check in @(
    @{ collection = 'semanticModels'; id = $state.semanticModelId },
    @{ collection = 'dataAgents'; id = $state.dataAgentId }
)) {
    Invoke-Fabric -Method GET -Path "workspaces/$($state.workspaceId)/$($check.collection)/$($check.id)" | Out-Null
}
[string[]]$validationFiles = if ($CheckRestrictedIdentity) {
    @((Join-Path $PSScriptRoot '..\database\security\002_test_restricted_reader.sql'))
} else {
    @((Join-Path $PSScriptRoot '..\fabric\warehouse\004_validate_analytics.sql'))
}
& py -3.12 (Join-Path $PSScriptRoot 'Invoke-SqlWithAccessToken.py') `
    --server $state.warehouseSqlEndpoint --database 'CommunityHealthAnalyticsWH' `
    --tenant-id $TenantId @validationFiles
if ($LASTEXITCODE -ne 0) { throw 'Reporting data or requested SQL identity checks failed.' }
if ($CheckRestrictedIdentity) {
    Write-Host 'PASS: mirroring, item existence, SQL reporting access, and raw appointment access denial for this identity.'
} else {
    Write-Host 'PASS: mirroring, completed analytics pipeline, item existence, nonempty reporting tables, suppression, and reporting keys.'
}
Write-Warning 'These checks do not prove agent answer accuracy, ontology refresh, publication, or OneLake permissions. Complete the presenter acceptance checklist.'
