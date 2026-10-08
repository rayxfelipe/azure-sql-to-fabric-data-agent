[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$SessionDirectory = Join-Path $PSScriptRoot '..\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0'
$FabricStateFile = Join-Path $SessionDirectory 'fabric-deployment.json'

if (-not (Test-Path -LiteralPath $FabricStateFile)) {
    throw 'Fabric deployment state is missing.'
}

$state = Get-Content -LiteralPath $FabricStateFile -Raw | ConvertFrom-Json
$token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Unable to acquire a Fabric token.' }
$mirrorStatusJson = curl.exe --http1.1 --retry 5 --retry-all-errors --silent --show-error --fail-with-body `
    -X POST `
    -H "Authorization: Bearer $token" `
    --data '' `
    "https://api.fabric.microsoft.com/v1/workspaces/$($state.workspaceId)/mirroredDatabases/$($state.mirroredDatabaseId)/getMirroringStatus"
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to retrieve Fabric mirroring status.'
}
$mirrorStatus = $mirrorStatusJson | ConvertFrom-Json
if ($mirrorStatus.status -notin @('Running', 'Running with warning', 'Started')) {
    throw "Mirroring is not running. Current status: $($mirrorStatus.status)"
}

$validationQuery = @"
SET NOCOUNT ON;
SELECT 'FactAppointment' AS EntityName, COUNT_BIG(*) AS SampleRowCount FROM analytics.FactAppointment
UNION ALL SELECT 'FactReferral', COUNT_BIG(*) FROM analytics.FactReferral
UNION ALL SELECT 'FactCapacity', COUNT_BIG(*) FROM analytics.FactCapacity;
IF NOT EXISTS (SELECT 1 FROM analytics.FactAppointment)
    THROW 51011, 'FactAppointment is empty.', 1;
IF NOT EXISTS (SELECT 1 FROM analytics.FactReferral)
    THROW 51012, 'FactReferral is empty.', 1;
IF NOT EXISTS (SELECT 1 FROM analytics.FactCapacity)
    THROW 51013, 'FactCapacity is empty.', 1;
IF EXISTS (SELECT 1 FROM analytics.vw_CommunityHealthAccess WHERE AppointmentCount < 11)
    THROW 51010, 'Small-cell suppression validation failed.', 1;
"@
$queryFile = Join-Path $SessionDirectory 'fabric-validation.sql'
$validationQuery | Set-Content -LiteralPath $queryFile -Encoding utf8
try {
    & py -3.12 (Join-Path $PSScriptRoot 'Invoke-SqlWithAccessToken.py') `
        --server $state.warehouseSqlEndpoint `
        --database 'CommunityHealthAnalyticsWH' `
        $queryFile
    if ($LASTEXITCODE -ne 0) { throw 'Fabric Warehouse validation failed.' }
}
finally {
    Remove-Item -LiteralPath $queryFile -Force -ErrorAction SilentlyContinue
}

Write-Host 'End-to-end mirroring, warehouse row counts, and small-cell suppression checks passed.'
