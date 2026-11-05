# Azure Deployment Plan

> **Status:** Validated for the non-destructive Fabric-only repair and ontology retry; live acceptance pending.
>
> The repository repair adds nonempty physical reporting tables, a real refresh
> pipeline, corrected measures, and a new five-entity ontology with declared
> Warehouse backing in the existing companion workspace. Live SQL and seven DAX
> known-answer cases passed. The native analytics pipeline, full model refresh,
> agent publication, and seven published natural-language known answers subsequently
> passed. Graph materialization, ontology-context format compatibility, and effective
> permission acceptance remain outstanding. Authentication is restored after the initial blocked
> attempt. ARM infrastructure redeployment is explicitly excluded. Use the [presenter runbook](../docs/presenter-runbook.md) and
> [current summary](../docs/deployment-summary.md); historical checks below are not
> proof of current data, publication, ontology binding, or effective permissions.

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
| Visualization | Warehouse queries/model exploration; report not authored | Existing Fabric surfaces |
| Domain model | Fabric IQ Ontology | Preview |
| Natural-language analytics | Fabric Data Agent | Fabric workload |

### Security and Privacy

- Synthetic data only; no real PHI or direct identifiers.
- Aggregate-first analytics with small-cell suppression.
- TLS-encrypted Azure SQL connectivity.
- Entra-only authentication is enforced; no SQL password is generated or stored.
- Azure SQL public access is disabled; the deployed source uses private endpoint/DNS and a Fabric VNet gateway.
- The source connection uses the dedicated Entra service principal, not OAuth2 user credentials. Existing administrator configuration is not replaced unless explicitly requested.
- Physical reporting tables enforce the demo's record-count suppression before model/ontology consumption. SQL role tests alone do not prove OneLake, workspace, model, or published-agent isolation.

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

**Historical status:** Initial resources were within limits. The legacy companion
workspace/capacity was subsequently added for an unbound conceptual ontology.
The repair provisions no additional capacity. The standalone ontology retry
explicitly reused that existing companion after the primary returned
`FeatureNotAvailable`; current capacity/access state must be checked before rehearsal.

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

The following is the original execution checklist, not a current readiness record.
For the revised existing-environment upgrade, use the runbook's go/no-go checklist.
Agent A publication is explicit through `-PublishDataAgent`; ontology-context
attachment still needs compatible preview support. Do not commit or push without
explicit authorization.

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

These are historical estimates, not current quotes. A second legacy F8 may also
incur charges while active. Pause each capacity actually used; SQL/storage charges
continue independently.

---

## 9. Validation Proof

### 2026-11-04: limited Fabric-only repair and ontology retry

Scope: upgrade the already-approved synthetic source and existing Fabric items,
then attempt the new backed ontology in the primary workspace, with the existing
approved companion used after a concrete feature rejection. **No ARM
infrastructure deployment, resource deletion, capacity reassignment, or SQL
administrator replacement is authorized by this retry.**

| Check | Command/evidence | Result |
|-------|------------------|--------|
| Approved identity | Tenant-targeted Fabric token; workspace lookup; current caller role | PASS: both project workspaces accessible; caller Admin in primary workspace |
| Existing capacities | Explicit-subscription ARM GET for the two approved capacities | PASS: both already Active; no power-state changes made |
| Core validation | Skill `validate-deployment.ps1`, subscription scope, West US 3, private hydrated parameters | PASS: CLI, authentication, Bicep build, ARM validation, and read-only what-if |
| Infrastructure drift | Same read-only what-if | Reported Create 2 / Modify 16 / Delete 10 change lines. **Not approved to apply**; counts can include nested property changes. No ARM deployment will run. |
| Lint | `az bicep lint --file .\infra\main.bicep` | PASS with existing API-type/environment-URL warnings |
| Policy | Explicit approved-subscription inherited policy assignment listing and ARM validation | PASS: three existing security initiatives; no validation denial |
| Build/contracts | Python 3.12 unittest suite and `Test-FabricHelpers.ps1` | PASS: 23 Python tests and 9 mocked helper checks |
| Static roles | Existing vault-scoped Secrets Officer assignment and Fabric/source identity flow | Reviewed; no new ARM roles or administrator changes proposed for this retry |
| Existing Warehouse | Tenant-targeted SQL connection and reporting preflight | Connected successfully; new reporting tables absent, so the authorized baseline upgrade must precede grounded ontology creation |

This is pre-deployment proof, not successful source refresh, ontology binding,
agent publication, or end-to-end acceptance. Those require subsequent live checks.

### November 4-5 live repair outcome

- Source initialization job `23e2fa4c-9427-431e-b13a-0925f80f2db8` completed using the
  existing private source connection. The mirror was resumed from Paused.
- Additive Warehouse schemas, five reporting tables, direct transactional refresh,
  and nonempty/privacy/key/relationship validation succeeded. Reported appointments
  total 70,944; referrals 12,000; weighted wait approximately 18.97 days.
- The existing semantic model definition and full refresh succeeded without
  DirectQuery fallback. All seven live DAX question-bank cases passed on November 5
  after the capacities, subsequently found Paused, were briefly resumed.
- Primary ontology creation returned HTTP 403 `FeatureNotAvailable`, request ID
  `9fd5474f-e151-4d31-952a-f129dc9de901`.
- Created `CCSF_Community_Health_Demo_Ontology`,
  `08fc9ac6-3cce-463f-81d4-b177d6548d19`, in the existing companion workspace
  `2cd38c5e-ce17-4ce8-84ee-83aa55b34a2d`. All 17 definition parts were retrieved;
  five table/property bindings and four relationship declarations were checked.
  The legacy ontology was preserved.
- The ontology editor now renders five entities/four relationships. Graph projection
  reports Ineligible/Unsupported Datasource, including after a governed-only
  Lakehouse-shortcut trial. The live definition was restored to Warehouse/reporting
  through the standalone source-template updater; all 17 parts read back.
- The actual analytics pipeline completed with a native Warehouse item binding,
  without a new cloud SQL connection. Full model refresh and Agent A publication
  succeeded. All seven published MCP known answers matched the canonical fixture;
  four negative prompts disclosed no prohibited result, with two generic service
  safety refusals. Native PowerShell HTTP/1.1 avoided observed Python transport
  connection timeouts.
- Draft B context attachment was rejected because the service requires the legacy
  root `definition.json` while this new ontology returns TMDL. Graph runtime,
  published B/fair A-B comparison, and restricted-identity checks remain outstanding.
- No ARM deployment, new capacity/workspace, cross-region reassignment, credential
  rotation, or SQL administrator replacement was performed.
- Both capacities were verified Paused again after the final model checks.

These are component-specific results, not full-demo or permission acceptance.

### Historical infrastructure validation

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
- Existing ontology-only companion: `ws-e2e-sql-to-fabricagent-iq` on
  `fabriccapacitydemo001`, West US; reused, not newly provisioned or reassigned.
- No resources may be created outside these boundaries.
- No real PHI may be used.

---

## 12. Historical Deployment Result

- **Completed:** `2026-10-08`
- **Status:** Deployed and validated with documented feature limitations.
- **Policy:** `AzureSQL_WithoutAzureADOnlyAuthentication_Deny` in the `MCAPSGovDenyPolicies` initiative.
- **Resolution:** The design uses Entra-only Azure SQL, private networking, a Fabric VNet Data Gateway, and a dedicated service principal.
- **Second policy:** Tenant governance also enforced private-only Azure SQL networking. The deployment added a VNet, private endpoint, private DNS, and a subnet delegated to `Microsoft.PowerPlatform/vnetaccesslinks`.
- **Deployed:** Azure foundation, deterministic synthetic SQL data, private Fabric connection, running mirror, loaded Warehouse, pipelines, Direct Lake semantic model, Data Agent, and a generation-2 Ontology in the companion Fabric IQ workspace.
- **Validated:** Mirroring `Running`; Warehouse facts nonempty; small-cell threshold of 11 enforced.
- **Ontology topology:** The primary West US 3 workspace cannot be reassigned across regions to the West US capacity. `CCSF_Community_Health_Ontology` is deployed in `ws-e2e-sql-to-fabricagent-iq` on `fabriccapacitydemo001`; it is modeled but unbound because no compatible Lakehouse or Eventhouse source is present there.
- **Capacity state:** `fabriccapacitydemo001` and `fabriccapacitydemo001b` are active for the customer demonstration.
- **Policy bypass:** None attempted.
