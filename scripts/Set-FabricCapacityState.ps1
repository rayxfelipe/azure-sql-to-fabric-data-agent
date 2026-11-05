[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Resume', 'Suspend')][string]$State,
    [ValidateSet('Primary', 'LegacyOntology', 'All')][string]$Target = 'Primary'
)

$ErrorActionPreference = 'Stop'
$subscriptionId = 'd6721f8a-9863-4f84-b7e6-c6e857272fec'
$capacities = @{
    Primary = 'fabriccapacitydemo001b'
    LegacyOntology = 'fabriccapacitydemo001'
}
$names = if ($Target -eq 'All') { @($capacities.Primary, $capacities.LegacyOntology) } else { @($capacities[$Target]) }
$action = if ($State -eq 'Resume') { 'resume' } else { 'suspend' }
$expected = if ($State -eq 'Resume') { 'Active' } else { 'Paused' }
foreach ($name in $names) {
    $resourceIds = @(az resource list --subscription $subscriptionId --resource-type Microsoft.Fabric/capacities --name $name --query '[].id' --output tsv)
    if ($LASTEXITCODE -ne 0 -or $resourceIds.Count -ne 1) { throw "Expected one accessible approved capacity named $name." }
    $resourceId = $resourceIds[0]
    $current = az resource show --subscription $subscriptionId --ids $resourceId --query properties.state --output tsv
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect approved capacity $name." }
    if ($current -ne $expected) {
        az resource invoke-action --subscription $subscriptionId --ids $resourceId --action $action --api-version 2023-11-01 --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Unable to $action capacity $name." }
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $current = az resource show --subscription $subscriptionId --ids $resourceId --query properties.state --output tsv
            if ($LASTEXITCODE -ne 0) { throw "Cannot verify capacity $name." }
            if ($current -eq $expected) { break }
            Start-Sleep -Seconds 5
        }
        if ($current -ne $expected) { throw "Capacity $name did not reach $expected." }
    }
    Write-Host "$name is $expected."
}
