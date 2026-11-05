[CmdletBinding()]
param(
    [string]$SqlServicePrincipalClientId,
    [string]$SqlServicePrincipalObjectId,
    [string]$SqlServicePrincipalDisplayName,
    [securestring]$SqlServicePrincipalSecret,
    [string]$SqlServicePrincipalTenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb',
    [string]$WarehouseConnectionId,
    [string]$OntologyWorkspaceName = 'ws-e2e-sql-to-fabricagent-iq',
    [switch]$PublishDataAgent,
    [switch]$InitializeSource,
    [switch]$ConfigureSqlAdministrator,
    [switch]$UpdateExistingOntology
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$CapacityId = 'c23c22ae-da71-49b2-b620-8612df1259dc'
$WorkspaceName = 'ws-e2e-sql-to-fabricagent'
$SessionDirectory = Join-Path $PSScriptRoot '..\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0'
$AzureDeploymentFile = Join-Path $SessionDirectory 'azure-deployment.json'
$StateFile = Join-Path $SessionDirectory 'fabric-deployment.json'
. (Join-Path $PSScriptRoot 'Fabric-Helpers.ps1')

if (-not (Test-Path -LiteralPath $AzureDeploymentFile)) {
    throw 'Azure deployment state is missing. Run Deploy-Azure.ps1 first.'
}
$azure = Get-Content -LiteralPath $AzureDeploymentFile -Raw | ConvertFrom-Json
Connect-Fabric -TenantId $SqlServicePrincipalTenantId
if ($ConfigureSqlAdministrator) {
    if (-not $SqlServicePrincipalObjectId -or -not $SqlServicePrincipalDisplayName) {
        throw 'Configuring the SQL administrator requires the service principal object ID and display name.'
    }
    az sql server ad-admin update --subscription $azure.subscriptionId `
        --resource-group $azure.resourceGroupName --server-name $azure.sqlServerName `
        --display-name $SqlServicePrincipalDisplayName --object-id $SqlServicePrincipalObjectId `
        --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to configure the explicitly requested SQL administrator.' }
}

$workspace = Get-FabricCollection -Path 'workspaces' |
    Where-Object displayName -eq $WorkspaceName | Select-Object -First 1
if (-not $workspace) {
    $workspace = Invoke-Fabric -Method POST -Path 'workspaces' -Body @{
        displayName = $WorkspaceName
        description = 'Synthetic CCSF community-health SQL-to-Fabric demonstration.'
    }
}
$workspaceId = $workspace.id
if (-not $workspaceId) { throw 'Fabric did not return a workspace ID.' }
if (-not $workspace.capacityId) {
    Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/assignToCapacity" -Body @{ capacityId = $CapacityId } | Out-Null
}
elseif ($workspace.capacityId -ne $CapacityId) {
    throw 'The demo workspace is assigned to an unexpected capacity. No cross-region reassignment was attempted.'
}

$gateway = Get-FabricCollection -Path 'gateways' |
    Where-Object displayName -eq 'gw-e2e-sql-to-fabricagent' | Select-Object -First 1
if (-not $gateway) {
    $gateway = Invoke-Fabric -Method POST -Path 'gateways' -Body @{
        displayName = 'gw-e2e-sql-to-fabricagent'
        capacityId = $CapacityId
        inactivityMinutesBeforeSleep = 30
        numberOfMemberGateways = 1
        type = 'VirtualNetwork'
        virtualNetworkAzureResource = @{
            subscriptionId = $azure.subscriptionId
            resourceGroupName = $azure.resourceGroupName
            virtualNetworkName = $azure.virtualNetworkName
            subnetName = $azure.fabricGatewaySubnetName
        }
    }
}
$roles = @(Get-FabricCollection -Path "workspaces/$workspaceId/roleAssignments")
if (-not ($roles | Where-Object { $_.principal.id -eq $azure.sqlServerPrincipalId })) {
    Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/roleAssignments" -Body @{
        principal = @{ id = $azure.sqlServerPrincipalId; type = 'ServicePrincipal' }
        role = 'Contributor'
    } | Out-Null
}

$connections = @(Get-FabricCollection -Path 'connections')
$sqlConnection = $connections | Where-Object displayName -eq 'CommunityHealthAzureSql' | Select-Object -First 1
if (-not $sqlConnection) {
    if (-not $SqlServicePrincipalClientId -or -not $SqlServicePrincipalSecret) {
        throw 'A new private Azure SQL connection requires the service principal client ID and secure secret. Existing connections are reused without retrieving credentials.'
    }
    $plainSecret = [Net.NetworkCredential]::new('', $SqlServicePrincipalSecret).Password
    $sqlConnection = Invoke-Fabric -Method POST -Path 'connections' -Body @{
        connectivityType = 'VirtualNetworkGateway'
        gatewayId = $gateway.id
        displayName = 'CommunityHealthAzureSql'
        connectionDetails = @{
            type = 'SQL'
            creationMethod = 'SQL'
            parameters = @(
                @{ dataType = 'Text'; name = 'server'; value = $azure.sqlServerFullyQualifiedDomainName },
                @{ dataType = 'Text'; name = 'database'; value = $azure.sqlDatabaseName }
            )
        }
        privacyLevel = 'Organizational'
        credentialDetails = @{
            singleSignOnType = 'None'
            connectionEncryption = 'Encrypted'
            skipTestConnection = $false
            credentials = @{
                credentialType = 'ServicePrincipal'
                servicePrincipalClientId = $SqlServicePrincipalClientId
                servicePrincipalSecret = $plainSecret
                tenantId = $SqlServicePrincipalTenantId
            }
        }
        allowUsageInUserControlledCode = $true
    }
    $plainSecret = $null
}

$sourceScripts = @()
foreach ($file in @('..\database\schema\001_oltp_schema.sql', '..\database\seed\002_seed_synthetic.sql', '..\database\validation\004_validate_source.sql')) {
    $sql = Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw
    foreach ($batch in [regex]::Split($sql, '(?im)^\s*GO\s*$')) {
        if (-not [string]::IsNullOrWhiteSpace($batch)) {
            $sourceScripts += @{ type = 'NonQuery'; text = $batch.Trim() }
        }
    }
}
$sourceDefinition = @{
    properties = @{
        description = 'Non-destructively upserts and validates the synthetic source through the private VNet gateway.'
        activities = @(@{
            name = 'InitializeSyntheticAzureSql'
            type = 'Script'
            dependsOn = @()
            policy = @{ timeout = '0.01:00:00'; retry = 1; retryIntervalInSeconds = 30; secureInput = $false; secureOutput = $false }
            externalReferences = @{ connection = $sqlConnection.id }
            typeProperties = @{
                database = @{ name = $azure.sqlDatabaseName }
                scripts = $sourceScripts
                scriptBlockExecutionTimeout = '00:30:00'
            }
        })
    }
}
$sourcePipeline = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'dataPipelines' `
    -DisplayName 'pl_initialize_azure_sql_source' -Description 'Upserts the deterministic synthetic Azure SQL source.' `
    -Parts @((ConvertTo-InlinePart -Path 'pipeline-content.json' -Content ($sourceDefinition | ConvertTo-Json -Depth 100)))
$existingMirror = Get-WorkspaceItem -WorkspaceId $workspaceId -Collection 'mirroredDatabases' -DisplayName 'CommunityHealthOLTP_Mirror'
if (-not $existingMirror -or $InitializeSource) {
    Start-FabricPipeline -WorkspaceId $workspaceId -PipelineId $sourcePipeline.id | Out-Null
}

$mirrorContent = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\mirroring\mirroring.template.json') -Raw).
    Replace('{{CONNECTION_ID}}', $sqlConnection.id)
$mirror = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'mirroredDatabases' `
    -DisplayName 'CommunityHealthOLTP_Mirror' -Description 'Synthetic community-health source mirrored into OneLake.' `
    -Parts @((ConvertTo-InlinePart -Path 'mirroring.json' -Content $mirrorContent))
$mirrorStatus = Start-FabricMirroring -WorkspaceId $workspaceId -MirrorId $mirror.id
if ($mirrorStatus.status -eq 'Running with warning') { Write-Warning 'Inspect the mirroring warning before presenting.' }

$warehouse = Get-WorkspaceItem -WorkspaceId $workspaceId -Collection 'warehouses' -DisplayName 'CommunityHealthAnalyticsWH'
if (-not $warehouse) {
    $warehouse = Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/warehouses" -Body @{
        displayName = 'CommunityHealthAnalyticsWH'
        description = 'Synthetic source facts and physical, privacy-filtered reporting tables.'
    }
}
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $warehouse = Invoke-Fabric -Method GET -Path "workspaces/$workspaceId/warehouses/$($warehouse.id)"
    if ($warehouse.properties.connectionString) { break }
    Start-Sleep -Seconds 5
}
$warehouseEndpoint = $warehouse.properties.connectionString
if (-not $warehouseEndpoint) { throw 'The Warehouse SQL endpoint did not become ready.' }
& py -3.12 (Join-Path $PSScriptRoot 'Invoke-SqlWithAccessToken.py') `
    --server $warehouseEndpoint --database 'CommunityHealthAnalyticsWH' `
    --tenant-id $SqlServicePrincipalTenantId `
    (Join-Path $PSScriptRoot '..\fabric\warehouse\001_analytics_schema.sql') `
    (Join-Path $PSScriptRoot '..\fabric\warehouse\002_privacy_views.sql') `
    (Join-Path $PSScriptRoot '..\database\security\001_reporting_role.sql')
if ($LASTEXITCODE -ne 0) { throw 'Warehouse schema or privacy-view deployment failed.' }

$loadSql = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\warehouse\003_refresh_analytics.sql') -Raw
$validationSql = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\warehouse\004_validate_analytics.sql') -Raw
$pipelineDefinition = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\pipeline\pipeline-content.template.json') -Raw | ConvertFrom-Json
$activity = $pipelineDefinition.properties.activities[0]
$activity.linkedService.properties.typeProperties.endpoint = $warehouseEndpoint
$activity.linkedService.properties.typeProperties.artifactId = $warehouse.id
$activity.linkedService.properties.typeProperties.workspaceId = $workspaceId
if ($WarehouseConnectionId) {
    $activity.PSObject.Properties.Remove('linkedService')
    $activity | Add-Member -NotePropertyName externalReferences -NotePropertyValue @{ connection = $WarehouseConnectionId }
    $activity.typeProperties | Add-Member -NotePropertyName database -NotePropertyValue @{ name = 'CommunityHealthAnalyticsWH' }
}
$activity.typeProperties.scripts[0].text = "$loadSql`n$validationSql"
$pipeline = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'dataPipelines' `
    -DisplayName 'pl_load_community_health_analytics' `
    -Description 'Transactionally refreshes and validates the physical reporting tables.' `
    -Parts @((ConvertTo-InlinePart -Path 'pipeline-content.json' -Content ($pipelineDefinition | ConvertTo-Json -Depth 100)))
$pipelineJob = Start-FabricPipeline -WorkspaceId $workspaceId -PipelineId $pipeline.id

$replacements = @{ '{{WAREHOUSE_SQL_ENDPOINT}}' = $warehouseEndpoint }
$semanticRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\fabric\semantic-model')).Path
$semanticModel = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'semanticModels' `
    -DisplayName 'Community Health Access Model' -Description 'Direct Lake over physical, privacy-filtered reporting tables.' `
    -Parts @(Get-DefinitionParts -Root $semanticRoot -Replacements $replacements)
Start-FabricSemanticModelRefresh -TenantId $SqlServicePrincipalTenantId `
    -WorkspaceId $workspaceId -SemanticModelId $semanticModel.id | Out-Null

$ontology = $null
$ontologyWorkspace = if ($OntologyWorkspaceName -eq $WorkspaceName) { $workspace } else {
    Get-FabricCollection -Path 'workspaces' | Where-Object displayName -eq $OntologyWorkspaceName | Select-Object -First 1
}
if (-not $ontologyWorkspace) {
    throw "Ontology workspace '$OntologyWorkspaceName' was not found. No workspace or capacity was provisioned automatically."
}
$ontologyStatus = 'Not attempted.'
$ontologyRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\fabric\ontology')).Path
try {
    $priorOntology = Get-WorkspaceItem -WorkspaceId $ontologyWorkspace.id -Collection 'ontologies' -DisplayName 'CCSF_Community_Health_Demo_Ontology'
    $ontology = New-DefinitionItem -WorkspaceId $ontologyWorkspace.id -Collection 'ontologies' `
        -DisplayName 'CCSF_Community_Health_Demo_Ontology' `
        -Description 'Five governed entities bound to reporting tables, with no client-level source.' `
        -Parts @(Get-DefinitionParts -Root $ontologyRoot -Replacements $replacements) `
        -PreserveExisting:(-not $UpdateExistingOntology)
    $ontologyStatus = if ($priorOntology -and -not $UpdateExistingOntology) {
        'Existing definition preserved unchanged; inspect its actual bindings and refresh in the portal.'
    } else {
        'Definition created or updated with declared Warehouse bindings; portal verification required.'
    }
}
catch {
    if ($_.Exception.Message -notmatch 'FeatureNotAvailable|feature is not available') { throw }
    $ontologyStatus = 'Not deployed: Ontology preview is unavailable in this workspace. Follow the runbook fallback; no companion workspace was automatically created.'
    Write-Warning $ontologyStatus
}

$datasource = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\datasource.template.json') -Raw).
    Replace('{{SEMANTIC_MODEL_ID}}', $semanticModel.id).Replace('{{WORKSPACE_ID}}', $workspaceId)
$dataAgent = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'dataAgents' `
    -DisplayName 'SFDPH Community Health Analyst' -Description 'Aggregate-only synthetic community-health analyst.' `
    -Parts @(
        (ConvertTo-InlinePart -Path 'Files/Config/data_agent.json' -Content (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\data_agent.json') -Raw)),
        (ConvertTo-InlinePart -Path 'Files/Config/draft/semantic_model-CommunityHealthAccessModel/datasource.json' -Content $datasource),
        (ConvertTo-InlinePart -Path 'Files/Config/draft/semantic_model-CommunityHealthAccessModel/fewshots.json' -Content (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\fewshots.json') -Raw)),
        (ConvertTo-InlinePart -Path 'Files/Config/draft/stage_config.json' -Content (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\stage_config.json') -Raw))
    )
if ($PublishDataAgent) {
    Publish-FabricDataAgent -WorkspaceId $workspaceId -DataAgentId $dataAgent.id
}

[ordered]@{
    tenantId = $SqlServicePrincipalTenantId
    workspaceId = $workspaceId
    workspaceName = $WorkspaceName
    capacityId = $CapacityId
    gatewayId = $gateway.id
    sqlConnectionId = $sqlConnection.id
    sourceInitializationPipelineId = $sourcePipeline.id
    mirroredDatabaseId = $mirror.id
    warehouseId = $warehouse.id
    warehouseSqlEndpoint = $warehouseEndpoint
    warehouseConnectionId = $WarehouseConnectionId
    pipelineId = $pipeline.id
    analyticsPipelineJobId = $pipelineJob.id
    analyticsPipelineJobStatus = $pipelineJob.status
    analyticsPipelineJobCompletedAt = $pipelineJob.endTimeUtc
    semanticModelId = $semanticModel.id
    ontologyWorkspaceId = $ontologyWorkspace.id
    ontologyWorkspaceName = $ontologyWorkspace.displayName
    ontologyCapacityId = $ontologyWorkspace.capacityId
    ontologyId = $ontology.id
    ontologyStatus = $ontologyStatus
    ontologyAgentAttachmentStatus = 'Manual preview step: add ontology context to a second agent and complete presenter acceptance checks.'
    dataAgentId = $dataAgent.id
    agentPublicationStatus = if ($PublishDataAgent) { 'Published configuration verified; run MCP question-bank acceptance before presenting.' } else { 'Draft updated; prior published configuration preserved. Publish explicitly before evaluating the new draft.' }
    reportStatus = 'No report generated. The runbook uses Warehouse queries, semantic model exploration, and agents.'
    deployedAt = [DateTimeOffset]::Now.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding utf8

Write-Host "Fabric baseline refreshed. Ontology: $ontologyStatus Complete portal acceptance using docs\presenter-runbook.md."
