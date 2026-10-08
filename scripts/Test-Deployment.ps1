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
$headers = @{ Authorization = "Bearer $token" }

$mirrorStatus = Invoke-RestMethod -Method Get `
    -Uri "https://api.fabric.microsoft.com/v1/workspaces/$($state.workspaceId)/mirroredDatabases/$($state.mirroredDatabaseId)/getMirroringStatus" `
    -Headers $headers
if ($mirrorStatus.status -notin @('Running', 'Started')) {
    throw "Mirroring is not running. Current status: $($mirrorStatus.status)"
}

$validationQuery = @"
SET NOCOUNT ON;
SELECT 'FactAppointment' AS EntityName, COUNT_BIG(*) AS RowCount FROM analytics.FactAppointment
UNION ALL SELECT 'FactReferral', COUNT_BIG(*) FROM analytics.FactReferral
UNION ALL SELECT 'FactCapacity', COUNT_BIG(*) FROM analytics.FactCapacity;
IF EXISTS (SELECT 1 FROM analytics.vw_CommunityHealthAccess WHERE AppointmentCount < 11)
    THROW 51010, 'Small-cell suppression validation failed.', 1;
"@
$queryFile = Join-Path $SessionDirectory 'fabric-validation.sql'
$validationQuery | Set-Content -LiteralPath $queryFile -Encoding utf8
try {
    & sqlcmd -S $state.warehouseSqlEndpoint -d 'CommunityHealthAnalyticsWH' -G -N -b -i $queryFile
    if ($LASTEXITCODE -ne 0) { throw 'Fabric Warehouse validation failed.' }
}
finally {
    Remove-Item -LiteralPath $queryFile -Force -ErrorAction SilentlyContinue
}

Write-Host 'End-to-end mirroring, warehouse row counts, and small-cell suppression checks passed.'
