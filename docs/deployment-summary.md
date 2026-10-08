# Deployment Summary

## Result

The private synthetic community-health data path is deployed and validated:

`Azure SQL Database -> Fabric Mirroring -> Fabric Warehouse -> Direct Lake semantic model -> Fabric Data Agent`

All data is synthetic. No real PHI or direct identifiers are present.

## Azure

| Resource | Name | State |
|----------|------|-------|
| Resource group | `rg-e2e-sql-to-fabricagent` | Deployed |
| Azure SQL server | `sql-e2e-fabricagent-dev-3af2` | Ready; Entra-only; public access disabled |
| Azure SQL database | `sqldb-community-health` | S3 / 100 DTU |
| Virtual network | `vnet-e2e-fabricagent` | Deployed |
| Private endpoint and DNS | SQL private access | Approved and operational |
| Key Vault | `kv-e2e-fabric-3af2` | Deployed |

## Microsoft Fabric

Workspace: `ws-e2e-sql-to-fabricagent`

| Item | ID | State |
|------|----|-------|
| VNet data gateway | `30e1ee2d-f9d4-4b9a-9240-678ea58b5276` | Deployed |
| Azure SQL connection | `a691b72e-6f04-4b87-a6c9-4827dc4a9bfa` | Encrypted service-principal credential |
| Source initialization pipeline | `400a308d-ceae-49d6-82da-144da1f161df` | Completed |
| Mirrored database | `66474c57-5cf4-4930-82a8-6cdab5f8b4e6` | Running |
| Warehouse | `a987c2d4-af3a-47c4-881d-9092d05e2c78` | Loaded |
| Analytics pipeline | `c12039f9-7d16-427a-8c0c-9d803f0ff68c` | Created |
| Semantic model | `08d658a3-a6ce-4b13-a821-676486f297cb` | Created |
| Data Agent | `cbc7c698-fa5b-4a48-bc51-9b80d6aca8d6` | Created |

## Validation

- Mirroring status: `Running`
- Warehouse facts: nonempty
- Small-cell suppression: no exposed aggregate below 11
- Local API: health, readiness, and synthetic-data endpoints passed
- Fabric F8 capacity: paused after validation

## Known Limitations

- Automated Ontology creation returned `FeatureNotAvailable` for the target workspace.
  Because Ontology is available in another workspace in the same tenant, this result
  does not establish a tenant-wide limitation. Portal availability and differences in
  capacity, region, or workspace eligibility require separate verification.
- Ontology attachment to Data Agent is a portal-only Preview workflow.
- A Power BI report was not generated because supported Fabric REST APIs require an
  existing report definition and do not document from-scratch visual authoring.

These limitations do not block testing the mirrored data, Warehouse, semantic model, or
Data Agent.

## Credential Rotation

The dedicated service principal is `sp-e2e-sql-to-fabricagent`. Its current credential
expires April 6, 2027 and is stored only in the encrypted Fabric connection. Rotate it
before expiration, update the Fabric connection, and rerun end-to-end validation.
