# Azure Deployment Plan

> **Status:** Deployed

Generated: 2026-10-07

---

## 1. Project Overview

**Goal:** Build and validate a synthetic healthcare-data demonstration from Azure SQL OLTP through Microsoft Fabric analytics, semantic model, ontology, and Data Agent.

**Path:** Add Components

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | POC |
| Scale | Small |
| Budget | Cost-Optimized |
| Subscription | ME-MngEnvMCAP081059-rayfelipe-1 (`d6721f8a-9863-4f84-b7e6-c6e857272fec`) |
| Location | `westus3` |

The subscription, region, resource group, existing Fabric capacity, and dedicated workspace boundary were explicitly approved by the user.

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Synthetic data utility | API | Python 3.12 / FastAPI / Pydantic / Faker | `src/community_health` |
| Azure infrastructure | Infrastructure | Bicep | `infra` |
| Azure SQL artifacts | Database | T-SQL | `database` |
| Fabric automation | Deployment tooling | PowerShell / Fabric REST API | `scripts` |
| Fabric definitions | Analytics | Fabric item definitions / TMDL | `fabric` |

---

## 4. Recipe Selection

**Selected:** Bicep

**Rationale:** The approved subscription-scope infrastructure is already represented as modular Bicep. Fabric resources require separate Fabric REST and TDS automation because they are not Azure Resource Manager resources.

---

## 5. Architecture

**Stack:** Azure SQL and Microsoft Fabric managed services

### Service Mapping

| Component | Azure/Fabric Service | SKU |
|-----------|----------------------|-----|
| Transactional source | Azure SQL Database | Standard S3 / 100 DTU |
| Secret storage | Azure Key Vault | Standard |
| Analytics capacity | Existing Microsoft Fabric capacity | F8, resumed only for deployment and validation |
| Replication | Fabric Mirrored Database | Capacity workload |
| Curated analytics | Fabric Warehouse | Capacity workload |
| Orchestration | Fabric Data Pipeline | Capacity workload |
| Business model | Power BI semantic model | Direct Lake |
| Visualization | Power BI report | Fabric report |
| Domain model | Fabric IQ Ontology | Preview |
| Natural-language analytics | Fabric Data Agent | Fabric workload |

### Security and Privacy

- Synthetic data only; no real PHI or direct identifiers.
- Aggregate-first analytics with small-cell suppression.
- TLS-encrypted Azure SQL connectivity.
- Entra-only authentication is enforced; no SQL password is generated or stored.
- Public SQL connectivity is limited to the administrator IP and Azure-services rule for this POC.
- The authenticated deployment user is configured as the Azure SQL Entra administrator and Fabric uses an OAuth2 organizational-account connection.

---

## 6. Provisioning Limit Checklist

| Resource Type | Number to Deploy | Total After Deployment | Limit/Quota | Notes |
|---------------|------------------|------------------------|-------------|-------|
| Microsoft.Resources/resourceGroups | 1 | 1 project RG | Subscription limit not constraining | Exact approved RG only |
| Microsoft.KeyVault/vaults | 1 | 1 project vault | Subscription limit not constraining | Name availability checked at deployment |
| Microsoft.Sql/servers | 1 | 1 in West US 3 | 250 servers; 0 previously used | Verified against Azure SQL regional quota |
| Microsoft.Sql/servers/databases | 1 | 1 S3 database | Within server/database limits | S3 selected because Fabric Mirroring requires at least 100 DTU |
| Microsoft.Fabric/capacities | 0 new | 1 existing F8 reused | No new quota required | `fabriccapacitydemo001b`; resume then pause |
| Fabric workspace | 1 | 1 dedicated workspace | Existing tenant/capacity access verified | `ws-e2e-sql-to-fabricagent` |

**Status:** All resources within limits.

---

## 7. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace
- [x] Gather requirements
- [x] Confirm subscription and location with user
- [x] Prepare resource inventory
- [x] Fetch quotas and validate capacity
- [x] Scan codebase
- [x] Select recipe
- [x] Plan architecture
- [x] User approved this plan through the explicit end-to-end deployment authorization

### Phase 2: Execution

- [x] Research Azure SQL and Fabric components
- [x] Generate initial infrastructure files
- [x] Apply initial security hardening
- [x] Generate database and Fabric artifacts
- [x] Run static functional verification (PowerShell parsing, JSON parsing, and Bicep compilation)
- [x] Validate infrastructure and deployment plan
  - [x] All validation checks pass
    - [x] Core Validation (CLI, auth, build, validate, what-if)
    - [x] Bicep linting
    - [x] Azure Policy validation

### Phase 3: Deployment

- [ ] Run subscription-scope what-if and verify zero deletes
- [ ] Deploy Azure resources
- [ ] Load deterministic synthetic data
- [ ] Resume existing F8 capacity
- [ ] Create dedicated Fabric workspace and items
- [ ] Validate the end-to-end data path and privacy controls
- [ ] Pause F8 capacity
- [ ] Update documentation, commit, and push

---

## 8. Cost Estimate

| Service | Estimated Cost |
|---------|----------------|
| Azure SQL Database S3 | Approximately $145.16/month |
| Azure Key Vault | Approximately $0.03/month at demo volume |
| Existing Fabric F8 | Approximately $1.44 per active hour; approximately $1,051.20/month if left active continuously |

The Fabric capacity must be paused after validation. The expected steady cost while Fabric is paused is approximately $145.19/month, excluding taxes, egress, OneLake overage, and licensing.

---

## 9. Validation Proof

Validated on `2026-10-07T18:26:58-07:00`.

| Check | Command | Result |
|-------|---------|--------|
| Core Bicep validation | `validate-deployment.ps1 -Scope sub -Location westus3 -Template .\infra\main.bicep -Parameters <private-validation-parameters> -Subscription d6721f8a-9863-4f84-b7e6-c6e857272fec` | PASS: CLI, authentication, Bicep compilation, ARM validation, and what-if |
| What-if changes | Included in core validation | PASS: Create 9, Modify 0, Delete 0 |
| Bicep lint | `az bicep lint --file .\infra\main.bicep` | PASS with three non-blocking BCP081 warnings caused by local type-registry lag for provider-listed Key Vault API `2026-05-15` |
| Python build | `py -3.12 -m compileall -q .\src .\main.py` | PASS |
| PowerShell and JSON parsing | PowerShell AST parser and `ConvertFrom-Json` over checked-in scripts/templates | PASS |
| Azure Policy | `az policy assignment list --scope <subscription> --disable-scope-strict-match` plus ARM validation | PASS: three inherited/security assignments reviewed; no deny-policy conflict |
| Static RBAC | Review of Bicep role assignments and Fabric workspace assignment flow | PASS |

---

## 10. Role Assignment Verification

- **Status:** Verified
- **Deployer identity:** Key Vault Secrets Officer, scoped to the project Key Vault, for post-deployment secret retrieval and administration.
- **Azure SQL managed identity:** No Azure data-plane role is required. The Fabric deployment script grants it Contributor on the dedicated Fabric workspace because Microsoft documents workspace role assignment as the REST alternative to the portal-only mirrored-item permission.
- **Fabric SQL identity:** Dedicated single-tenant service principal with no API permissions; configured as the Entra-only SQL administrator. Its sole 180-day credential is stored only in the encrypted Fabric connection.
- **Deployment caller:** Inherited Owner was verified at the tenant management-group scope.
- **Issues:** None.

---

## 11. Deployment Boundaries

- Azure tenant: `aa56606c-b0ba-43a8-9c11-eb0144a67efb`
- Azure subscription: `d6721f8a-9863-4f84-b7e6-c6e857272fec`
- Azure resource group: `rg-e2e-sql-to-fabricagent`
- Azure region: `westus3`
- Existing Fabric capacity: `fabriccapacitydemo001b`
- Fabric workspace: `ws-e2e-sql-to-fabricagent`
- No resources may be created outside these boundaries.
- No real PHI may be used.

---

## 12. Deployment Result

- **Completed:** `2026-10-08`
- **Status:** Deployed and validated with documented feature limitations.
- **Policy:** `AzureSQL_WithoutAzureADOnlyAuthentication_Deny` in the `MCAPSGovDenyPolicies` initiative.
- **Resolution:** The design uses Entra-only Azure SQL, private networking, a Fabric VNet Data Gateway, and a dedicated service principal.
- **Second policy:** Tenant governance also enforced private-only Azure SQL networking. The deployment added a VNet, private endpoint, private DNS, and a subnet delegated to `Microsoft.PowerPlatform/vnetaccesslinks`.
- **Deployed:** Azure foundation, deterministic synthetic SQL data, private Fabric connection, running mirror, loaded Warehouse, pipelines, Direct Lake semantic model, and Data Agent.
- **Validated:** Mirroring `Running`; Warehouse facts nonempty; small-cell threshold of 11 enforced.
- **Blocked by scoped setting:** Ontology creation returned `FeatureNotAvailable`, and the portal confirmed that the required Ontology creation tenant setting is not enabled for this workspace's current user or capacity scope. Ontology is available elsewhere in the tenant, so this is not a tenant-wide feature limitation. Supported REST APIs do not provide from-scratch visual report authoring.
- **Capacity safety:** `fabriccapacitydemo001b` was paused after validation.
- **Policy bypass:** None attempted.
