[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Resume', 'Suspend')]
    [string]$State
)

$ErrorActionPreference = 'Stop'
$SubscriptionId = 'd6721f8a-9863-4f84-b7e6-c6e857272fec'
$CapacityResourceId = '/subscriptions/d6721f8a-9863-4f84-b7e6-c6e857272fec/resourceGroups/rg-fabriccapacity-demo-001/providers/Microsoft.Fabric/capacities/fabriccapacitydemo001b'
$action = if ($State -eq 'Resume') { 'resume' } else { 'suspend' }

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to select the approved Azure subscription.'
}

az resource invoke-action --ids $CapacityResourceId --action $action --api-version 2023-11-01 --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Unable to $action the approved Fabric capacity."
}

Write-Host "Fabric capacity action '$action' completed."
