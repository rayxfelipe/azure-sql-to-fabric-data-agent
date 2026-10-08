[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SqlServicePrincipalClientId,
    [Parameter(Mandatory)][string]$SqlServicePrincipalObjectId,
    [Parameter(Mandatory)][string]$SqlServicePrincipalDisplayName,
    [Parameter(Mandatory)][securestring]$SqlServicePrincipalSecret,
    [string]$SqlServicePrincipalTenantId = 'aa56606c-b0ba-43a8-9c11-eb0144a67efb'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$FabricBaseUri = 'https://api.fabric.microsoft.com/v1'
$CapacityId = 'c23c22ae-da71-49b2-b620-8612df1259dc'
$WorkspaceName = 'ws-e2e-sql-to-fabricagent'
$SessionDirectory = Join-Path $PSScriptRoot '..\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0'
$AzureDeploymentFile = Join-Path $SessionDirectory 'azure-deployment.json'
$StateFile = Join-Path $SessionDirectory 'fabric-deployment.json'

if (-not (Test-Path -LiteralPath $AzureDeploymentFile)) {
    throw 'Azure deployment state is missing. Run Deploy-Azure.ps1 first.'
}

$azure = Get-Content -LiteralPath $AzureDeploymentFile -Raw | ConvertFrom-Json
$plainSqlServicePrincipalSecret = [Net.NetworkCredential]::new('', $SqlServicePrincipalSecret).Password
az sql server ad-admin update `
    --subscription $azure.subscriptionId `
    --resource-group $azure.resourceGroupName `
    --server-name $azure.sqlServerName `
    --display-name $SqlServicePrincipalDisplayName `
    --object-id $SqlServicePrincipalObjectId `
    --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to configure the supplied service principal as the Entra-only Azure SQL administrator.'
}
$token = (az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken --output tsv)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Unable to acquire a Microsoft Fabric access token.'
}
$headers = @{ Authorization = "Bearer $token" }
$fabricHttpClient = [Net.Http.HttpClient]::new()
$fabricHttpClient.DefaultRequestVersion = [Version]'1.1'
$fabricHttpClient.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)

function ConvertTo-InlinePart {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    @{
        path = $Path
        payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content))
        payloadType = 'InlineBase64'
    }
}

function Wait-FabricOperation {
    param([Parameter(Mandatory)][string]$Location)
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Seconds 5
        $operation = Invoke-Fabric -Method GET -Path $Location
        if ($operation.status -eq 'Succeeded') {
            if ($operation.resourceLocation) {
                return Invoke-Fabric -Method GET -Path $operation.resourceLocation
            }
            return $operation
        }
        if ($operation.status -eq 'Failed') {
            throw "Fabric operation failed: $($operation.error | ConvertTo-Json -Depth 20 -Compress)"
        }
    }
    throw "Fabric operation timed out: $Location"
}

function Invoke-Fabric {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )
    $uri = if ($Path.StartsWith('https://')) { $Path } else { "$FabricBaseUri/$($Path.TrimStart('/'))" }
    Write-Verbose "Fabric API $Method $Path"
    $response = $null
    $statusCode = 0
    $responseHeaders = $null
    for ($requestAttempt = 1; $requestAttempt -le 4; $requestAttempt++) {
        try {
            $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $uri)
            $request.Version = [Version]'1.1'
            if ($null -ne $Body) {
                $json = $Body | ConvertTo-Json -Depth 100 -Compress
                $request.Content = [Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, 'application/json')
            }
            $httpResponse = $fabricHttpClient.SendAsync($request).GetAwaiter().GetResult()
            $statusCode = [int]$httpResponse.StatusCode
            $responseHeaders = $httpResponse.Headers
            $content = $httpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $response = if ([string]::IsNullOrWhiteSpace($content)) { $null } else { $content | ConvertFrom-Json }
            break
        }
        catch {
            if ($requestAttempt -lt 4 -and $_.Exception.Message -match 'transport connection|forcibly closed|timed out|SSL connection') {
                Start-Sleep -Seconds (5 * $requestAttempt)
                continue
            }
            throw
        }
    }
    if ($statusCode -eq 202) {
        $location = [string]$responseHeaders.Location
        if (-not $location) {
            return $response
        }
        return Wait-FabricOperation -Location $location
    }
    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        throw "Fabric API $Method $Path failed with HTTP $statusCode`: $($response | ConvertTo-Json -Depth 20 -Compress)"
    }
    return $response
}

function Get-WorkspaceItem {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$Collection,
        [Parameter(Mandatory)][string]$DisplayName
    )
    $items = Invoke-Fabric -Method GET -Path "workspaces/$WorkspaceId/$Collection"
    return @($items.value) | Where-Object displayName -eq $DisplayName | Select-Object -First 1
}

function New-DefinitionItem {
    param(
        [Parameter(Mandatory)][string]$WorkspaceId,
        [Parameter(Mandatory)][string]$Collection,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][object[]]$Parts,
        [string]$Description
    )
    $existing = Get-WorkspaceItem -WorkspaceId $WorkspaceId -Collection $Collection -DisplayName $DisplayName
    if ($existing) {
        if ($Collection -ne 'mirroredDatabases') {
            Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/$Collection/$($existing.id)/updateDefinition" -Body @{
                definition = @{ parts = $Parts }
            } | Out-Null
        }
        return $existing
    }
    return Invoke-Fabric -Method POST -Path "workspaces/$WorkspaceId/$Collection" -Body @{
        displayName = $DisplayName
        description = $Description
        definition = @{ parts = $Parts }
    }
}

$workspaceList = Invoke-Fabric -Method GET -Path 'workspaces'
$workspace = @($workspaceList.value) | Where-Object displayName -eq $WorkspaceName | Select-Object -First 1
if (-not $workspace) {
    $workspace = Invoke-Fabric -Method POST -Path 'workspaces' -Body @{
        displayName = $WorkspaceName
        description = 'Synthetic CCSF DPH community-health SQL-to-Fabric demonstration.'
    }
}
$workspaceId = $workspace.id

Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/assignToCapacity" -Body @{ capacityId = $CapacityId } | Out-Null

$gateways = Invoke-Fabric -Method GET -Path 'gateways'
$gatewayName = 'gw-e2e-sql-to-fabricagent'
$gateway = @($gateways.value) | Where-Object displayName -eq $gatewayName | Select-Object -First 1
if (-not $gateway) {
    $gateway = Invoke-Fabric -Method POST -Path 'gateways' -Body @{
        displayName = $gatewayName
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

$roleAssignments = Invoke-Fabric -Method GET -Path "workspaces/$workspaceId/roleAssignments"
$miAssignment = @($roleAssignments.value) | Where-Object { $_.principal.id -eq $azure.sqlServerPrincipalId }
if (-not $miAssignment) {
    Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/roleAssignments" -Body @{
        principal = @{
            id = $azure.sqlServerPrincipalId
            type = 'ServicePrincipal'
        }
        role = 'Contributor'
    } | Out-Null
}

$connections = Invoke-Fabric -Method GET -Path 'connections'
$sqlConnectionName = 'CommunityHealthAzureSql'
$sqlConnection = @($connections.value) | Where-Object displayName -eq $sqlConnectionName | Select-Object -First 1
if (-not $sqlConnection) {
    $sqlConnection = Invoke-Fabric -Method POST -Path 'connections' -Body @{
        connectivityType = 'VirtualNetworkGateway'
        gatewayId = $gateway.id
        displayName = $sqlConnectionName
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
                servicePrincipalSecret = $plainSqlServicePrincipalSecret
                tenantId = $SqlServicePrincipalTenantId
            }
        }
        allowUsageInUserControlledCode = $true
    }
}

$sourceSqlFiles = @(
    '..\database\schema\001_oltp_schema.sql',
    '..\database\seed\002_seed_synthetic.sql',
    '..\database\validation\004_validate_source.sql'
)
$sourceScripts = [Collections.Generic.List[object]]::new()
foreach ($relativePath in $sourceSqlFiles) {
    $content = Get-Content -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Raw
    foreach ($batch in [regex]::Split($content, '(?im)^\s*GO\s*$')) {
        if (-not [string]::IsNullOrWhiteSpace($batch)) {
            $sourceScripts.Add(@{ type = 'NonQuery'; text = $batch.Trim() })
        }
    }
}
$sourceInitDefinition = @{
    properties = @{
        description = 'Initializes and validates the private Azure SQL synthetic source.'
        activities = @(
            @{
                name = 'InitializeSyntheticAzureSql'
                type = 'Script'
                dependsOn = @()
                policy = @{
                    timeout = '0.01:00:00'
                    retry = 1
                    retryIntervalInSeconds = 30
                    secureInput = $false
                    secureOutput = $false
                }
                externalReferences = @{ connection = $sqlConnection.id }
                typeProperties = @{
                    database = @{ name = $azure.sqlDatabaseName }
                    scripts = $sourceScripts
                    scriptBlockExecutionTimeout = '00:30:00'
                }
            }
        )
    }
} | ConvertTo-Json -Depth 100 -Compress
$sourceInitPipeline = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'dataPipelines' `
    -DisplayName 'pl_initialize_azure_sql_source' `
    -Description 'Creates and validates the deterministic synthetic Azure SQL source through the private VNet gateway.' `
    -Parts @((ConvertTo-InlinePart -Path 'pipeline-content.json' -Content $sourceInitDefinition))

$existingMirror = Get-WorkspaceItem -WorkspaceId $workspaceId -Collection 'mirroredDatabases' -DisplayName 'CommunityHealthOLTP_Mirror'
if (-not $existingMirror) {
    $sourceJobRequest = [Net.Http.HttpRequestMessage]::new(
        [Net.Http.HttpMethod]::Post,
        "$FabricBaseUri/workspaces/$workspaceId/items/$($sourceInitPipeline.id)/jobs/instances?jobType=Pipeline"
    )
    $sourceJobResponse = $fabricHttpClient.SendAsync($sourceJobRequest).GetAwaiter().GetResult()
    $sourceJobContent = $sourceJobResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ([int]$sourceJobResponse.StatusCode -notin @(200, 202)) {
        throw "Unable to start Azure SQL initialization pipeline: HTTP $([int]$sourceJobResponse.StatusCode) $sourceJobContent"
    }
    $sourceJobLocation = [string]$sourceJobResponse.Headers.Location
    if (-not $sourceJobLocation) {
        $sourceJobLocation = "$FabricBaseUri/workspaces/$workspaceId/items/$($sourceInitPipeline.id)/jobs/instances"
    }
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Seconds 10
        $jobs = Invoke-Fabric -Method GET -Path $sourceJobLocation
        $latestJob = if ($jobs.value) { @($jobs.value) | Sort-Object startTimeUtc -Descending | Select-Object -First 1 } else { $jobs }
        if ($latestJob.status -eq 'Completed') { break }
        if ($latestJob.status -in @('Failed', 'Cancelled', 'Deduped')) {
            throw "Azure SQL initialization pipeline ended in state '$($latestJob.status)': $($latestJob.failureReason | ConvertTo-Json -Depth 20 -Compress)"
        }
    }
    if ($latestJob.status -ne 'Completed') {
        throw 'Azure SQL initialization pipeline did not complete before timeout.'
    }
}

$mirroringTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\mirroring\mirroring.template.json') -Raw
$mirroringJson = $mirroringTemplate.Replace('{{CONNECTION_ID}}', $sqlConnection.id)
$mirror = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'mirroredDatabases' `
    -DisplayName 'CommunityHealthOLTP_Mirror' `
    -Description 'Synthetic Azure SQL community-health source mirrored into OneLake.' `
    -Parts @((ConvertTo-InlinePart -Path 'mirroring.json' -Content $mirroringJson))

$mirroringStarted = $false
for ($attempt = 0; $attempt -lt 6; $attempt++) {
    try {
        Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/mirroredDatabases/$($mirror.id)/startMirroring" | Out-Null
        $mirroringStarted = $true
        break
    }
    catch {
        if ($_.Exception.Message -notmatch 'OperationNotAllowedInCurrentStatus|Initializing') {
            throw
        }
        Start-Sleep -Seconds 10
    }
}
if (-not $mirroringStarted) {
    Write-Warning 'The mirrored database is still initializing. Remaining Fabric items will be provisioned while its SQL endpoint continues asynchronously.'
}

$warehouse = Get-WorkspaceItem -WorkspaceId $workspaceId -Collection 'warehouses' -DisplayName 'CommunityHealthAnalyticsWH'
if (-not $warehouse) {
    $warehouse = Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/warehouses" -Body @{
        displayName = 'CommunityHealthAnalyticsWH'
        description = 'Curated synthetic community-health analytics warehouse.'
    }
}

for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $warehouse = Invoke-Fabric -Method GET -Path "workspaces/$workspaceId/warehouses/$($warehouse.id)"
    if ($warehouse.properties.connectionString) { break }
    Start-Sleep -Seconds 5
}
if (-not $warehouse.properties.connectionString) {
    throw 'The Fabric Warehouse SQL endpoint did not become ready.'
}

$warehouseEndpoint = $warehouse.properties.connectionString
$schemaScript = Join-Path $PSScriptRoot '..\fabric\warehouse\001_analytics_schema.sql'
$viewsScript = Join-Path $PSScriptRoot '..\fabric\warehouse\002_privacy_views.sql'
& py -3.12 (Join-Path $PSScriptRoot 'Invoke-SqlWithAccessToken.py') `
    --server $warehouseEndpoint `
    --database 'CommunityHealthAnalyticsWH' `
    $schemaScript
if ($LASTEXITCODE -ne 0) { throw 'Fabric Warehouse schema creation failed.' }

$loadSql = @"
TRUNCATE TABLE analytics.FactCapacity;
TRUNCATE TABLE analytics.FactReferral;
TRUNCATE TABLE analytics.FactAppointment;
TRUNCATE TABLE analytics.DimClientSegment;
TRUNCATE TABLE analytics.DimProgram;
TRUNCATE TABLE analytics.DimFacility;
INSERT analytics.DimFacility SELECT FacilityId, FacilityName, Neighborhood, PlannedDailyCapacity FROM [CommunityHealthOLTP_Mirror].[health].[Facilities];
INSERT analytics.DimProgram SELECT ProgramId, FacilityId, ProgramName, ServiceCategory FROM [CommunityHealthOLTP_Mirror].[health].[Programs];
INSERT analytics.DimClientSegment SELECT ClientId, AgeBand, DemographicGroup, Neighborhood FROM [CommunityHealthOLTP_Mirror].[health].[Clients];
INSERT analytics.FactAppointment SELECT AppointmentId, ClientId, ProgramId, CAST(ScheduledAt AS date), WaitDays, AppointmentStatus FROM [CommunityHealthOLTP_Mirror].[health].[Appointments];
INSERT analytics.FactReferral SELECT ReferralId, ClientId, FromProgramId, ToProgramId, ReferralDate, ReferralStatus, DaysToClose FROM [CommunityHealthOLTP_Mirror].[health].[Referrals];
INSERT analytics.FactCapacity SELECT CapacitySnapshotId, FacilityId, SnapshotDate, AvailableSlots, BookedSlots FROM [CommunityHealthOLTP_Mirror].[health].[CapacitySnapshots];
"@

$temporaryLoadFile = Join-Path $SessionDirectory 'warehouse-load.sql'
$loadSql | Set-Content -LiteralPath $temporaryLoadFile -Encoding utf8
try {
    if ($mirroringStarted) {
        & py -3.12 (Join-Path $PSScriptRoot 'Invoke-SqlWithAccessToken.py') `
            --server $warehouseEndpoint `
            --database 'CommunityHealthAnalyticsWH' `
            $temporaryLoadFile `
            $viewsScript
        if ($LASTEXITCODE -ne 0) { throw 'Fabric Warehouse load or privacy-view creation failed.' }
    }
    else {
        Write-Warning 'Warehouse data load is deferred until mirroring can start.'
    }
}
finally {
    Remove-Item -LiteralPath $temporaryLoadFile -Force -ErrorAction SilentlyContinue
}

$pipeline = Get-WorkspaceItem -WorkspaceId $workspaceId -Collection 'dataPipelines' -DisplayName 'pl_load_community_health_analytics'
if (-not $pipeline) {
    $pipeline = Invoke-Fabric -Method POST -Path "workspaces/$workspaceId/dataPipelines" -Body @{
        displayName = 'pl_load_community_health_analytics'
        description = 'Curated load pipeline item. The deploy script executes the checked-in equivalent load SQL because a reusable Warehouse OAuth connection cannot be safely exported with credentials.'
    }
}

$semanticParts = @()
$semanticRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\fabric\semantic-model')).Path
Get-ChildItem -LiteralPath $semanticRoot -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($semanticRoot.Length + 1).Replace('\', '/')
    $content = Get-Content -LiteralPath $_.FullName -Raw
    if ($relative -eq 'definition/expressions.tmdl') {
        $content = $content.Replace('{{WAREHOUSE_SQL_ENDPOINT}}', $warehouseEndpoint)
    }
    $semanticParts += ConvertTo-InlinePart -Path $relative -Content $content
}
$semanticModel = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'semanticModels' `
    -DisplayName 'Community Health Access Model' `
    -Description 'Direct Lake measures over privacy-controlled synthetic community-health analytics.' `
    -Parts $semanticParts

$ontologyParts = @()
$ontologyRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\fabric\ontology')).Path
Get-ChildItem -LiteralPath $ontologyRoot -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($ontologyRoot.Length + 1).Replace('\', '/')
    $ontologyParts += ConvertTo-InlinePart -Path $relative -Content (Get-Content -LiteralPath $_.FullName -Raw)
}
$ontology = $null
$ontologyStatus = 'Created'
try {
    $ontology = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'ontologies' `
        -DisplayName 'Community Health Ontology' `
        -Description 'Synthetic community-health access domain ontology.' `
        -Parts $ontologyParts
}
catch {
    if ($_.Exception.Message -notmatch 'FeatureNotAvailable|feature is not available') {
        throw
    }
    $ontologyStatus = 'Not created: automated creation returned FeatureNotAvailable. Verify the Users can create Fabric items and Users can create ontology (preview) items tenant settings for the deployment identity or capacity.'
    Write-Warning $ontologyStatus
}

$datasource = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\datasource.template.json') -Raw).
    Replace('{{SEMANTIC_MODEL_ID}}', $semanticModel.id).
    Replace('{{WORKSPACE_ID}}', $workspaceId)
$agentParts = @(
    (ConvertTo-InlinePart -Path 'Files/Config/data_agent.json' -Content (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\data_agent.json') -Raw)),
    (ConvertTo-InlinePart -Path 'Files/Config/draft/semantic_model-CommunityHealthAccessModel/datasource.json' -Content $datasource),
    (ConvertTo-InlinePart -Path 'Files/Config/draft/semantic_model-CommunityHealthAccessModel/fewshots.json' -Content (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\fewshots.json') -Raw)),
    (ConvertTo-InlinePart -Path 'Files/Config/draft/stage_config.json' -Content (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\fabric\data-agent\stage_config.json') -Raw))
)
$dataAgent = New-DefinitionItem -WorkspaceId $workspaceId -Collection 'dataAgents' `
    -DisplayName 'SFDPH Community Health Analyst' `
    -Description 'Aggregate-only analyst for the synthetic community-health demonstration.' `
    -Parts $agentParts

[ordered]@{
    workspaceId = $workspaceId
    workspaceName = $WorkspaceName
    capacityId = $CapacityId
    gatewayId = $gateway.id
    sqlConnectionId = $sqlConnection.id
    sourceInitializationPipelineId = $sourceInitPipeline.id
    mirroredDatabaseId = $mirror.id
    warehouseId = $warehouse.id
    warehouseSqlEndpoint = $warehouseEndpoint
    pipelineId = $pipeline.id
    semanticModelId = $semanticModel.id
    ontologyId = $ontology.id
    ontologyStatus = $ontologyStatus
    dataAgentId = $dataAgent.id
    reportStatus = 'Not created: official REST APIs require an existing report definition; from-scratch visual authoring is not documented.'
    ontologyAgentAttachmentStatus = 'Not attached: ontology datasource attachment is portal-only Preview and not supported by the Data Agent definition schema.'
    deployedAt = [DateTimeOffset]::Now.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding utf8

Write-Host 'Fabric workspace, mirroring, warehouse, pipeline, semantic model, ontology, and Data Agent deployment completed.'
