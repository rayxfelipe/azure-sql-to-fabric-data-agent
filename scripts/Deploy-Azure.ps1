[CmdletBinding()]
param(
    [ValidateSet('WhatIf', 'Deploy')]
    [string]$Mode = 'WhatIf'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$SubscriptionId = 'd6721f8a-9863-4f84-b7e6-c6e857272fec'
$TenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb'
$Location = 'westus3'
$DeploymentName = 'e2e-sql-to-fabricagent-3af2'
$SessionDirectory = Join-Path $PSScriptRoot '..\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0'
$AuditFile = Join-Path $SessionDirectory 'deploy-audit.log'
$TemplateFile = Join-Path $PSScriptRoot '..\infra\main.bicep'
$ParametersFile = Join-Path $PSScriptRoot '..\infra\main.parameters.json'

function Write-Audit {
    param([string]$Message)
    Add-Content -LiteralPath $AuditFile -Value ('{0:o} {1}' -f [DateTimeOffset]::Now, $Message)
}

function Invoke-Az {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$AuditText
    )
    if ($AuditText) {
        Write-Audit $AuditText
    }
    else {
        Write-Audit ('az ' + ($Arguments -join ' '))
    }
    $output = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }
    return $output
}

New-Item -ItemType Directory -Path $SessionDirectory -Force | Out-Null

$account = Invoke-Az -Arguments @('account', 'show', '--output', 'json') | ConvertFrom-Json
if ($account.tenantId -ne $TenantId) {
    throw "Authenticated tenant '$($account.tenantId)' does not match approved tenant '$TenantId'."
}
if ($account.id -ne $SubscriptionId) {
    Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
}

$armToken = (Invoke-Az -Arguments @('account', 'get-access-token', '--resource', 'https://management.azure.com/', '--query', 'accessToken', '--output', 'tsv')).Trim()
$payload = $armToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
switch ($payload.Length % 4) {
    2 { $payload += '==' }
    3 { $payload += '=' }
}
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
$deployerObjectId = $claims.oid
$deployerPrincipalName = if ($claims.upn) { $claims.upn } elseif ($claims.preferred_username) { $claims.preferred_username } else { $account.user.name }
if (-not $deployerObjectId -or -not $deployerPrincipalName) {
    throw 'The Azure access token does not contain the required Entra user identity claims.'
}
$commonArguments = @(
    '--subscription', $SubscriptionId,
    '--location', $Location,
    '--template-file', $TemplateFile,
    '--parameters', "@$ParametersFile",
    '--parameters',
    "deployerObjectId=$deployerObjectId",
    "deployerPrincipalName=$deployerPrincipalName"
)

if ($Mode -eq 'WhatIf') {
    Invoke-Az -Arguments (@(
        'deployment', 'sub', 'what-if',
        '--name', $DeploymentName,
        '--no-pretty-print'
    ) + $commonArguments) -AuditText 'az deployment sub what-if (secure parameters redacted)'
    exit 0
}

$result = Invoke-Az -Arguments (@(
    'deployment', 'sub', 'create',
    '--name', $DeploymentName,
    '--only-show-errors',
    '--output', 'json'
) + $commonArguments) -AuditText 'az deployment sub create (secure parameters redacted)' | ConvertFrom-Json

if ($result.properties.provisioningState -ne 'Succeeded') {
    throw "Azure deployment ended in state '$($result.properties.provisioningState)'."
}

$outputs = $result.properties.outputs
$server = $outputs.sqlServerFullyQualifiedDomainName.value
$database = $outputs.sqlDatabaseName.value

[ordered]@{
    subscriptionId = $SubscriptionId
    resourceGroupName = $outputs.resourceGroupName.value
    keyVaultName = $outputs.keyVaultName.value
    sqlServerName = $outputs.sqlServerName.value
    sqlServerFullyQualifiedDomainName = $server
    sqlDatabaseName = $database
    sqlServerPrincipalId = $outputs.sqlServerPrincipalId.value
    virtualNetworkName = $outputs.virtualNetworkName.value
    fabricGatewaySubnetName = $outputs.fabricGatewaySubnetName.value
    virtualNetworkId = $outputs.virtualNetworkId.value
    deployedAt = [DateTimeOffset]::Now.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $SessionDirectory 'azure-deployment.json') -Encoding utf8

Write-Host 'Azure SQL and private networking deployment completed successfully.'
