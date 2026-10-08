targetScope = 'subscription'

@minLength(1)
@maxLength(64)
param environmentName string

@minLength(1)
param location string

param sessionId string
param deployedBy string
param createdAt string
param deployerObjectId string
param deployerPrincipalName string

var tags = {
  'app-onboard-skill': 'true'
  'app-onboard-session-id': sessionId
  'created-at': createdAt
  environment: environmentName
  'deployed-by': deployedBy
}

var resourceGroupName = 'rg-e2e-sql-to-fabricagent'
var keyVaultName = 'kv-e2e-fabric-3af2'
var sqlServerName = 'sql-e2e-fabricagent-dev-3af2'
var sqlDatabaseName = 'sqldb-community-health'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module keyVault './modules/key-vault.bicep' = {
  name: 'key-vault'
  scope: rg
  params: {
    keyVaultName: keyVaultName
    location: location
    tags: tags
  }
}

module sql './modules/sql-server.bicep' = {
  name: 'sql-server'
  scope: rg
  params: {
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    location: location
    tags: tags
    administratorLogin: deployerPrincipalName
    administratorObjectId: deployerObjectId
    tenantId: tenant().tenantId
  }
}

module networking './modules/networking.bicep' = {
  name: 'networking'
  scope: rg
  params: {
    location: location
    tags: tags
    sqlServerId: sql.outputs.sqlServerId
    sqlServerName: sqlServerName
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  scope: rg
  dependsOn: [
    keyVault
  ]
  params: {
    keyVaultName: keyVaultName
    deployerObjectId: deployerObjectId
  }
}

output resourceGroupName string = resourceGroupName
output keyVaultName string = keyVaultName
output sqlServerName string = sqlServerName
output sqlDatabaseName string = sqlDatabaseName
output sqlServerPrincipalId string = sql.outputs.sqlServerPrincipalId
output sqlServerFullyQualifiedDomainName string = sql.outputs.sqlServerFullyQualifiedDomainName
output virtualNetworkName string = networking.outputs.virtualNetworkName
output fabricGatewaySubnetName string = networking.outputs.fabricGatewaySubnetName
output virtualNetworkId string = networking.outputs.virtualNetworkId
