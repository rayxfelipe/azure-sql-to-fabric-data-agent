param sqlServerName string
param sqlDatabaseName string
param location string
param tags object
param administratorLogin string
param administratorObjectId string
param tenantId string

resource sqlServer 'Microsoft.Sql/servers@2025-01-01' = {
  name: sqlServerName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: administratorLogin
      sid: administratorObjectId
      tenantId: tenantId
      azureADOnlyAuthentication: true
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2025-01-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: 'S3'
    tier: 'Standard'
    capacity: 100
  }
}

output sqlServerId string = sqlServer.id
output sqlDatabaseId string = sqlDatabase.id
output sqlServerPrincipalId string = sqlServer.identity.principalId
output sqlServerFullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
