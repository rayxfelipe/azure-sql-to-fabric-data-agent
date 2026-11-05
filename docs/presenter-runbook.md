# Presenter runbook: from answers to trustworthy answers

## Readiness and scope

**The baseline SQL-to-published-agent demo is accepted; the ontology runtime/A-B
extension is not.** The private source, mirror, real analytics pipeline, governed
reporting tables, semantic-model update/full refresh, and publication succeeded.
SQL, all seven live DAX checks, and all seven published natural-language known
answers matched the answer card. The suppression explanation was corrected and
retested. Four negative prompts disclosed no prohibited result; the small-group
and clinical prompts returned generic service safety refusals, not the desired
explanations. This is a scripted synthetic rehearsal, not proof of arbitrary accuracy.

The primary workspace returned `403 FeatureNotAvailable`. The new item is
[here in the companion workspace](https://app.fabric.microsoft.com/groups/2cd38c5e-ce17-4ce8-84ee-83aa55b34a2d/ontologies/08fc9ac6-3cce-463f-81d4-b177d6548d19?ctid=aa56606c-b0ba-43a8-9c11-eb0144a67efb).
Its editor now loads in a fresh browser tab and shows five entities/four
relationships. **Manage graph** reports all five entities Ineligible with
"Unsupported Datasource". A same-workspace `CommunityHealthOntologyLH` containing
only five OneLake shortcuts to governed reporting tables was also tried; no
materialized graph or instance traversal has been accepted.

Agent B exists as a draft, but the ontology-context service rejected attachment:
it requires a root `definition.json` part while this new ontology returns TMDL.
That is a preview-format compatibility failure, not a remaining sign-in problem.
Do not fabricate the missing part or publish an empty B. Restricted-identity
SQL/OneLake/model/agent tests are also not run.

The actual Warehouse pipeline completed using native Warehouse item authentication.
A separate SQL/OAuth cloud connection and its blocked popup are **not required**
for the baseline. Both capacities must be Active for the complete workspace
walkthrough; resume them before rehearsal and pause them afterward.

The story is: **operational data -> replicated data -> governed aggregates ->
consistent measures -> business context -> independently checked answers.**
Use synthetic community-health service access, referrals, and capacity; never imply
these are actual CCSF findings. Wait-time differences are deliberately programmed
into the fixture, and other modular seed formulas also create artificial correlations.
This is not a statistically representative population or a clinical application.

Recommended length: 35-40 minutes, plus an optional five-minute change demonstration.
If rehearsal fails, use the baseline-only or discussion fallback in section 10.
Do not troubleshoot preview features in front of the customer.

### Names to keep open in browser tabs

| Surface | Name |
|---|---|
| Primary workspace | `ws-e2e-sql-to-fabricagent` |
| Azure SQL database | `sqldb-community-health` |
| Mirrored database | `CommunityHealthOLTP_Mirror` |
| Warehouse | `CommunityHealthAnalyticsWH` |
| Source initialization pipeline | `pl_initialize_azure_sql_source` |
| Analytics refresh pipeline | `pl_load_community_health_analytics` |
| Semantic model | `Community Health Access Model` |
| Agent A, existing name retained | `SFDPH Community Health Analyst` |
| New ontology | `CCSF_Community_Health_Demo_Ontology` |
| Ontology workspace | `ws-e2e-sql-to-fabricagent-iq` (existing companion) |
| Agent B, existing unaccepted draft | `SFDPH Community Health Analyst - Ontology` |
| Optional governed OneLake projection | `CommunityHealthOntologyLH` |

No Power BI report has been authored. Use Warehouse queries, semantic-model
exploration, and agents rather than promising a report dashboard.

## 1. Prepare and upgrade before the meeting

Allow at least 45-60 minutes for rehearsal, including replication and preview delays.
Commands below run from the repository root in **PowerShell 7.4+**, with Azure CLI,
Python 3.12, application requirements, `pyodbc`, and ODBC Driver 18 available.
Do not deploy into a different signed-in tenant as a workaround.

```powershell
az login --tenant aa56606c-b0ba-43a8-9c11-eb0144a67efb
az account show --subscription d6721f8a-9863-4f84-b7e6-c6e857272fec --query '{tenant:tenantId,subscription:id}' --output json
.\scripts\Set-FabricCapacityState.ps1 -State Resume -Target All
```

Confirm the displayed tenant and subscription match those arguments. In Fabric,
select the same directory and open the primary workspace. The capacity helper
uses the explicit approved subscription; it does not change the active subscription.
The new ontology also uses the existing companion capacity, so the full demo needs
both capacities Active. For a SQL/model-only rehearsal, use `-Target Primary` to
avoid running the companion unnecessarily. Do not infer capacity state from a
workspace listing or an old successful refresh.

### Verify the native Warehouse binding

The analytics Script activity now uses an inline `DataWarehouse` linked service
with the Warehouse endpoint, item ID, and workspace ID. This exact native binding
was persisted and successfully executed. No new secret, OAuth popup, cloud SQL
connection, or permission grant was required.

Inspect the activity's actual Warehouse selection and refresh/validation SQL.
`-WarehouseConnectionId` remains an explicit alternative for an already-tested
Script-compatible cloud SQL connection; omit it for the proven native default.
Do not pass the private Azure SQL source connection as that override.

The existing private source connection, `CommunityHealthAzureSql`, is reused without
retrieving its secret. Do not enable public access on the Azure SQL server.
Fresh deployment requires the approved private gateway and securely supplied
service-principal credential; this runbook upgrades the existing environment.

### Run the non-destructive upgrade

```powershell
.\scripts\Deploy-Fabric.ps1 -InitializeSource -PublishDataAgent
```

`-InitializeSource` runs additive source schema initialization and deterministic
upserts through the private source pipeline. It does not drop the source database
or delete extra synthetic records. It refuses to seed tables containing
non-synthetic rows. It is not a general-purpose production migration tool.
The deployment does not replace the SQL administrator unless explicitly requested.

The script updates/runs the real analytics activity, updates and fully refreshes the
semantic model, and updates agent A's draft. `-PublishDataAgent` then publishes it
and verifies the published configuration. Without that flag, publication is not
claimed. The existing companion is the default ontology workspace; an existing
ontology is preserved unless explicitly told to update it. No workspace move,
new capacity, administrator replacement, or credential rotation is implicit.
Ontology graph and ontology-context acceptance remain separate from this baseline.

If replication has not caught up, refresh validation fails explicitly; wait for
the mirror tables, then rerun the analytics pipeline. Do not lower row-count guards
or the suppression threshold to force a green result. After a successful deployment:

```powershell
.\scripts\Test-Deployment.ps1
```

If the deployment stops before writing new local state, use the portal and SQL
checks below; do not assume the previous state file describes the attempted upgrade.

## 2. Verify each layer and record the actual answers

### Source and mirror

Open the mirrored database's replication monitor. Check **each required table**,
not just the overall Running status. A mirror can remain **Paused** even when its
capacity is Active; the deployment helper now starts Paused mirrors explicitly.
Do not treat old per-table "Replicating" labels with old sync timestamps as current
replication. In its SQL analytics endpoint, run:

```sql
SELECT COUNT_BIG(*) AS Clients FROM health.Clients;
SELECT COUNT_BIG(*) AS Appointments FROM health.Appointments;
SELECT COUNT_BIG(*) AS Referrals FROM health.Referrals;
SELECT COUNT_BIG(*) AS CapacitySnapshots FROM health.CapacitySnapshots;
```

Canonical counts are **5,000 / 90,000 / 12,000 / 540**. Existing extra synthetic
rows, including the optional pulse, change these totals. Mirroring is asynchronous:
say "near-real-time replication," not "instantaneous" or "no transformation needed."

### Warehouse and pipeline

Open `pl_load_community_health_analytics`; verify its Script activity has the native
Warehouse selection and actual refresh/validation SQL, then **Run** and inspect
the successful output. This revised template executed successfully in this tenant.
The full-deployment pipeline job `79c02f3b-7a7b-466a-b25c-87ddb39e7aca` completed on
November 5; prefer the current deployment state and monitor over that historical example.

Run [analytics validation](../fabric/warehouse/004_validate_analytics.sql) in the
Warehouse query editor. It must return nonempty governed data, valid unique keys,
valid relationships/utilization, and no appointment/referral group below 11.
The refresh rebuilds internal facts and materialized reporting tables in a
transaction; a failed refresh rolls back rather than replacing good data with
empty reporting tables. The current pipeline is a **full refresh**, not an
incremental CDC transformation.

Run these independent ground-truth queries:

```sql
SELECT
    SUM(AppointmentCount) AS ReportedAppointments,
    SUM(CompletedCount) AS CompletedAppointments,
    SUM(NoShowCount) AS NoShows,
    SUM(WaitDaysTotal) AS WaitDaysTotal,
    SUM(WaitDaysTotal)*1.0/NULLIF(SUM(AppointmentCount),0) AS WeightedWaitDays,
    MIN(AppointmentCount) AS MinimumVisibleGroup
FROM reporting.CommunityHealthAccess;

SELECT ServiceCategory, SUM(AppointmentCount) AS ReportedAppointments,
       SUM(WaitDaysTotal)*1.0/NULLIF(SUM(AppointmentCount),0) AS WeightedWaitDays
FROM reporting.CommunityHealthAccess
GROUP BY ServiceCategory
ORDER BY WeightedWaitDays DESC;

SELECT SUM(ReferralCount) AS Referrals, SUM(CompletedReferralCount) AS Completed,
       SUM(CompletedReferralCount)*1.0/NULLIF(SUM(ReferralCount),0) AS CompletionRate
FROM reporting.ReferralPerformance;

SELECT COUNT(*) AS SeptemberSnapshotsAbove85Percent
FROM reporting.FacilityCapacity
WHERE SnapshotDate >= '2026-09-01' AND SnapshotDate < '2026-10-01'
  AND UtilizationRate > 0.85;
```

### Canonical answer card, before the optional pulse

| Check | Expected |
|---|---:|
| Source appointments | 90,000 |
| Reported appointments | 70,944 |
| Visible appointment groups | 5,163 |
| Suppressed appointment groups | 2,137 of 7,300 |
| Completed reported appointments | 42,556 |
| Reported no-shows | 14,077 |
| Total reported wait days | 1,345,727 |
| Weighted wait | 18.968862765 days, approximately 19.0 |
| No-show rate | Approximately 19.8% |
| Minimum visible appointment group | 11 |
| Reported referrals / completed | 12,000 / 6,000 |
| Referral completion | 50% |
| Referral groups / records per group | 300 / 40 |
| Capacity snapshots | 540 |
| September 2026 snapshots above 85% | 11 |

| Service category | Reported appointments | Weighted wait, days |
|---|---:|---:|
| Behavioral Health | 14,092 | 32.54 |
| Referral Services | 14,395 | 25.55 |
| Community Wellness | 14,305 | 15.56 |
| Preventive Services | 13,979 | 11.55 |
| Primary Care | 14,173 | 9.55 |

**70,944 is not 90,000:** the reporting layer excludes suppressed appointment
groups. Do not label it "all appointments," "unique clients," or a population rate.
Suppression counts records at the declared reporting grain, not distinct people;
it is an illustrative control, not a proof of production disclosure protection
under arbitrary filters or repeated queries. Capacity snapshots are non-person-level.

### Semantic model

Open `Community Health Access Model`, verify credentials/source access, and run a
refresh to reframe Direct Lake after table changes. Explore the model and confirm
`Appointments`, `Average Wait Days`, `No-Show Rate`, `Referral Completion Rate`, and
capacity results agree with SQL. Partitions now target **physical reporting tables**,
not SQL views. `directLakeOnly` intentionally surfaces problems rather than silently
falling back to DirectQuery. Do not silently relax it during a governance demonstration.

`Average Wait Days` is total wait days divided by appointments. The hidden,
pre-averaged column is not an approved measure. Different tables have different
grains; do not multiply counts by joining appointment and referral summaries together.

## 3. Publish and rehearse baseline agent A

1. Open `SFDPH Community Health Analyst` and confirm its source is the intended
   semantic model and all three reporting tables are selected. An empty selection
   is a real "No tables selected" runtime failure, not shorthand for selecting all.
2. Inspect instructions/examples, start a fresh test conversation, and ask the first,
   fourth, and sixth questions from the [question bank](../fabric/data-agent/evaluation_questions.json).
   Inspect generated DAX where the UI exposes it; compare with the independent SQL.
3. Use `-PublishDataAgent` or publish in the portal. Open the published experience and repeat the
   questions; draft success does not prove published success.
4. Keep a working published-agent tab ready. Use fixed dates such as September 2026
   or "entire dataset," not "last month" against a fixed-date fixture.

If either the published agent or model fails, do not claim the baseline is ready.
Instructions are guidance, not access controls or proof of answer accuracy.

### Repeat the published MCP rehearsal without UI dependence

Use the [native runner](../scripts/Invoke-FabricDataAgent.ps1), exercised against the
real published endpoint. It uses a single bounded question deadline, validates
JSON-RPC IDs/JSON/SSE responses, records failures when an output file is supplied,
and never prints tokens. Azure CLI authentication has a separate 60-second bound.

```powershell
$state = Get-Content '.\.copilot-azure\sessions\3af2326f-c8f1-4018-b73a-1542e5e709c0\fabric-deployment.json' -Raw | ConvertFrom-Json
.\scripts\Invoke-FabricDataAgent.ps1 `
    -WorkspaceId $state.workspaceId -DataAgentId $state.dataAgentId `
    -Question 'How many reported appointments are in the entire synthetic reporting dataset? Explain whether suppressed groups are included.' `
    -OutputFile '.\.copilot-azure\presenter-agent-answer.json'
```

Ask every question and negative case from the bank in fresh requests and inspect
the complete text. A transport `Completed`/`isError: false` is not an accuracy or
safety pass. Compare values, scope, suppression explanation, and unsupported-metric
claims independently. The reporting model cannot determine the source/omitted
counts; absence of a literal "Suppressed" category does not mean zero source suppression.

The optional [Python MCP runner](../scripts/Invoke-FabricDataAgent.py) uses
[requirements-demo.txt](../requirements-demo.txt) in an isolated environment.
It returned real answers but also encountered HTTPS connection timeouts here; the
same questions completed through the native runner. Do not call a connection
timeout a wrong agent answer or quietly omit failed attempts.

## 4. Create, bind, and inspect the ontology

The new ontology has **five declared backed entities**, not the legacy seven conceptual
entities. It intentionally models summaries rather than individual clients/cases.

| Entity | Physical backing table | Key |
|---|---|---|
| Facility | `reporting.Facilities` | `FacilityId` |
| Program | `reporting.Programs` | `ProgramId` |
| AccessSummary | `reporting.CommunityHealthAccess` | `AccessGroupId` |
| ReferralSummary | `reporting.ReferralPerformance` | `ReferralGroupId` |
| CapacitySnapshot | `reporting.FacilityCapacity` | `CapacitySnapshotId` |

Relationships: **Program -> Facility; AccessSummary -> Program;
ReferralSummary -> Program; CapacitySnapshot -> Facility.**
Neighborhood is a bound facility attribute, not a separate entity. No client,
individual appointment/referral, unbound outcome, or invented travel-distance
entity is promised.

If the baseline is ready but ontology was not created, retry independently:

```powershell
.\scripts\Deploy-Ontology.ps1 -WorkspaceName 'ws-e2e-sql-to-fabricagent-iq'
```

This validates reporting data first, preserves an existing item by default, and
reads the returned definition. A retrieved definition proves neither graph refresh
nor correct agent execution. Existing definitions are not silently upgraded.

After the Lakehouse-source trial, the live definition was deliberately restored
to the checked-in Warehouse/reporting bindings using `-UpdateExisting`; all 17
parts read back successfully. The trial Lakehouse and its five shortcuts remain
available, but are not the current ontology source or proof of a working graph.

In the existing companion workspace (the primary still rejects ontology creation):

1. Open `CCSF_Community_Health_Demo_Ontology`. Verify five entity types and all four
   relationships; inspect the actual source, key, and property-column mappings.
2. Confirm every binding points to `reporting`, not raw `analytics` facts. Inspect
   `AccessSummary` to distinguish a dated demographic aggregate from an appointment.
3. Refresh the ontology's data/graph using the portal. Inspect a facility, its
   programs, an access summary, and a capacity snapshot; confirm properties resolve
   to actual rows. An empty graph is a failed rehearsal, not a successful ontology.
4. If the API rejects the revised preview definition, record the error rather than
   classifying every failure as feature unavailability. If the portal supports it,
   inspect or repair the new item there, bind the five primary-workspace Warehouse reporting tables, select the
   keys above, and configure the four actual key relationships. Export that
   working definition for review.
5. If the editor reports Ineligible/Unsupported Datasource, stop the live graph
   branch and use the baseline fallback. A same-workspace Lakehouse with five
   governed OneLake shortcuts was prepared and tested without proving graph
   materialization. A new workspace/capacity was therefore not provisioned.
   Do not assume capacity or sign-in changes repair an unsupported-source result.

Current documentation supports Warehouse and semantic-model bindings; the older
"Lakehouse/Eventhouse only" explanation is no longer generally valid. Actual
availability still depends on tenant, region, permissions, and preview rollout.
The historical `ws-e2e-sql-to-fabricagent-iq` item remains untouched.

## 5. Add ontology context to agent B and compare fairly

**Conditional, not ready in this deployment.** The attempted attachment to the
new TMDL ontology failed with "missing the required root 'definition.json' part".
The existing B draft is not published or accepted. The steps below describe
acceptance after the service supports this ontology format; they are not results
already obtained. Do not label schema rendering or attaching an older unbound
conceptual ontology as equivalent acceptance.

1. Open the draft `SFDPH Community Health Analyst - Ontology`, or create one if absent.
   In the supported portal experience, add/select the new **ontology context** and
   configure its associated queryable data source as required by the UI. Use the
   five governed Warehouse reporting tables, not raw facts. Check the preview/runtime
   settings required by the current feature.
2. Give it the same aggregate-only, synthetic-data, fixed-date, no-invented-metrics
   instructions as A. For Warehouse query examples, use the question bank's
   `expected_sql`, not DAX examples intended for agent A's semantic model.
3. Refresh the agent's ontology context after ontology changes. Documentation allows
   up to ten minutes for context propagation unless manually refreshed. This is
   separate from Warehouse refresh, semantic-model framing, and ontology graph refresh.
4. Test draft B, publish it, and verify its published experience.
5. Ask both agents **identical** questions from the bank, using the same reporting
   snapshot, date filters, equivalent instructions, effective identity/permissions,
   and fresh conversations. Record answers, generated SQL/DAX, errors, and timing.

The context-only causal comparison is strongest when both agents use the same
underlying query source and configuration. This practical A/B setup can use
semantic-model measures for A and Warehouse SQL for B, so **source/engine differences
are a confounder**. Do not attribute a difference exclusively to ontology.
If the portal supports matching sources, create a matched-source comparison instead.
Supplemental ontology context has documented limitations for semantic-model sources;
do not assume that merely adding an ontology improves a semantic-model query.

Expected result: both agents should get the same scalar answers. Ontology makes
business terms, properties, and relationships inspectable; the underlying source
still executes DAX/SQL. It does not replace the semantic model, automatically repair
bad measures, add missing data, guarantee accuracy, or grant access.

Also ask one unavailable-metric question from `negativeCases`. A correct refusal
is a useful result. A prompt refusal alone is not a permission test.

## 6. Suggested live presentation, 35-40 minutes

| Time | Show | Say / verify |
|---|---|---|
| 0-3 min | Scope and architecture | "Entirely synthetic; today's focus is trustworthy service-access answers, not clinical advice." |
| 3-7 | Azure SQL tables/schema, then mirrored database | Explain operational relationships and private connectivity. Show replication health; avoid credentials and admin settings. |
| 7-12 | Analytics pipeline and Warehouse | Show the real refresh activity, safe reporting tables, suppression, and the 90,000 versus 70,944 distinction. |
| 12-17 | Semantic model and agent A | Ask total appointments and longest wait. Explain the weighted measure and independently checked answer. |
| 17-25 | Ontology mappings; graph only if accepted | Show five entity/four relationship declarations and reporting bindings. Disclose unsupported-source materialization; schema nodes are not row instances. |
| 25-31 | Verified agent A; conditional A/B | Today, repeat A's checked answers and discuss the new/legacy ontology-format gap. Show B only after separate published acceptance. No scripted "ontology wins." |
| 31-35 | Evaluation and access-control design | Show the recorded seven-answer rehearsal and negative cases. State restricted-identity enforcement is not yet demonstrated. |
| 35-40 | Ontology definitions/export and wrap-up | Demonstrate versionable definitions and deliberate redeployment. Discuss, but do not claim implementation of, other source systems. |

Useful prompts:

- "How many reported appointments are in the entire synthetic reporting dataset?"
- "Which service category has the longest appointment-weighted average wait?"
- "What percentage of reported referrals were completed?"
- "How many facility capacity snapshots exceeded 85 percent utilization during September 2026?"
- "Can you calculate population-adjusted utilization?" Expected: missing denominator.

Explain that programmed service bands make Behavioral Health the longest-wait
category in this fixture. Do not interpret that as a real disparity or a causal
finding. Do not claim encounters per resident, unique people served, median waits,
travel distances, clinical outcomes, or follow-up rates are implemented.

## 7. Optional live-change pulse

Rehearse this separately; skip it if timing or replication is uncertain.
The FastAPI application is an independent in-memory starter, **not** the cloud writer.

1. In Fabric, create a temporary pipeline Script activity using the existing private
   `CommunityHealthAzureSql` connection and database `sqldb-community-health`.
2. Paste [the pulse SQL](../database/seed/003_demo_pulse.sql), run once, and inspect
   success. It idempotently adds synthetic appointment `900001` by copying the
   visible-group fixture `365`; a second run does not add another row.
3. Wait until the mirror shows **90,001** source appointments.
4. Run `pl_load_community_health_analytics`; query the Warehouse independently.
   Reported appointments should increase **70,944 -> 70,945**, not remain unchanged
   because the new row was suppressed.
5. Refresh/reframe the semantic model, refresh the ontology graph, and refresh B's
   ontology context. Start fresh agent conversations and repeat the total question.
   Both agents should return **70,945** after all dependent surfaces are current.
6. If a layer lags, identify that layer. Do not describe a stale answer as a model
   hallucination until the source, reporting snapshot, and context are checked.

The seed intentionally preserves this extra row on rerun. To restore the canonical
fixture, run only the following targeted cleanup through the same private source
connection, then repeat replication and all refreshes:

```sql
DELETE FROM health.Appointments
WHERE AppointmentId = 900001 AND IsSynthetic = 1;
```

Do not drop/reseed the database. Fixed question-bank answers apply **before** the
pulse or after this cleanup; during the pulse, use current ground-truth SQL.

## 8. Known-answer evaluation and access checks

### Optional Fabric evaluation notebook

For an A/B run, first publish both accepted agents and verify the canonical fixture.
Today only A is accepted; omit B from the loop for an A-only evaluation. Upload
[evaluation_questions.json](../fabric/data-agent/evaluation_questions.json) to an
attached Lakehouse's `Files` area for the notebook. The Lakehouse here stores the
small test file/output only; it is not a new ontology backing-source requirement.
Use an existing approved notebook/Lakehouse if available; otherwise perform the
same checks manually rather than provisioning additional resources for the meeting.

```python
%pip install -U fabric-data-agent-sdk
```

In a subsequent notebook cell, using the documented SDK workflow:

```python
import json
import pandas as pd
from fabric.dataagent.evaluation import evaluate_data_agent

with open("/lakehouse/default/Files/evaluation_questions.json", encoding="utf-8") as file:
    bank = json.load(file)

df = pd.DataFrame([
    {"question": row["question"], "expected_answer": row["expected_answer"]}
    for row in bank["questions"]
])
evaluation_ids = {}
for name, table in [
    ("SFDPH Community Health Analyst", "demo_eval_semantic"),
    ("SFDPH Community Health Analyst - Ontology", "demo_eval_ontology"),
]:
    evaluation_ids[name] = evaluate_data_agent(
        df, name,
        workspace_name="ws-e2e-sql-to-fabricagent",
        table_name=table,
        data_agent_stage="production",
    )
evaluation_ids
```

This optional notebook evaluation has not been executed by the repository repair.
Inspect the returned evaluation runs/results. SDK judging is useful evidence,
not proof: additionally compare scalar values with `expected_sql`/`expected_dax`
and the bank's numeric tolerances. Rates use fractional values in SQL/DAX and
percentages in prose. Review negative cases manually. Record the data snapshot,
published stage, identity, model/context versions, and generated queries.

### Enforced access, not prompt-only protection

An administrator applies [the reporting role](../database/security/001_reporting_role.sql).
It grants SELECT on `reporting` and denies SELECT on `analytics`; it does not add
users automatically. Add an approved test principal using the supported Warehouse
identity/permission workflow. Use a **non-admin, non-Contributor** identity with only
the intended item/SQL access. Do not use the deploying identity as a restricted reader.

As that restricted identity, execute
[the negative SQL test](../database/security/002_test_restricted_reader.sql) in the
Warehouse. It must read nonempty reporting data and receive SQL permission error
229 when attempting raw appointments. Other errors or a readable raw table fail.
If that identity can also inspect the required Fabric items, the CLI alternative is:

```powershell
.\scripts\Test-Deployment.ps1 -CheckRestrictedIdentity
```

**SQL success is not proof of OneLake or agent-level isolation.** Separately inspect
workspace roles, item sharing, semantic-model Build/Read access, OneLake permissions
and effective identity. Test the actual published agent/model and any direct OneLake
path as the restricted identity. Workspace Admin/Contributor permissions can expose
raw data despite an illustrative SQL role. Source/table checkboxes and instructions
are not security boundaries. Mark unavailable identity tests **not run**, not passed.

## 9. Ontology as code: export, review, deliberately redeploy

Source templates live in [fabric/ontology](../fabric/ontology). To capture the actual
working item, get its IDs from the portal or successful ontology deployment output:

```powershell
.\scripts\Export-Ontology.ps1 `
    -WorkspaceId '<WORKSPACE-GUID>' -OntologyId '<ONTOLOGY-GUID>' `
    -OutputDirectory '.copilot-azure\ontology-export'
```

The ignored export directory prevents accidental check-in of an unreviewed live
definition. Use a fresh directory or explicitly pass `-Overwrite` when replacing
an earlier export. The script exports definition parts, not data rows.

Compare the export with the source in VS Code. For a small demo change, add/review
one business synonym or description in a backed entity, preserve valid property
bindings/relationships, and retain `{{WAREHOUSE_SQL_ENDPOINT}}` in source templates.
Preserve the table/column/expression `lineageTag` values: full source-template
updates failed without native source identities and succeeded with them restored.
Review all differences; do not blindly replace templates with environment-specific
exports or overwrite portal-curated bindings.

Stage only reviewed ontology definition changes through the normal Git workflow.
Keep local reference emails and deployment state out of version control.
Then explicitly apply the reviewed source:

```powershell
.\scripts\Deploy-Ontology.ps1 -WorkspaceName 'ws-e2e-sql-to-fabricagent-iq' -UpdateExisting
```

This replaces the item definition; export first. Default deployment preserves it.
Refresh the ontology and agent context, verify the edited term, and rerun known
answers. To roll back, deliberately deploy the prior reviewed definition and
repeat the same checks. Code versioning is not automatic graph/data rollback.

## 10. Go/no-go, fallbacks, and shutdown

Before calling the full demo ready, record each result:

- [x] Correct tenant/subscription and both existing capacities observed Active during repair.
- [x] Source upgrade completed; mirror resumed and upgraded source reached the Warehouse.
- [x] Actual analytics pipeline run completed; governed data nonempty and SQL checks pass.
- [x] Semantic-model refresh and all seven live DAX known-answer checks passed after capacity resume; repeat during rehearsal.
- [x] Agent A published; all seven canonical answers and suppression scope verified through published MCP.
- [x] New ontology accepted in the existing companion; five entity bindings/four relationships read back.
- [x] Ontology editor rendered the five-entity/four-relationship schema.
- [ ] Ontology graph materialization and source execution verified; currently Ineligible/Unsupported Datasource.
- [ ] Agent B context refreshed, published, and independently checked.
- [ ] Restricted-identity SQL, OneLake, model, and published-agent checks performed; untested paths disclosed.
- [x] Manual known-answer comparison used the same canonical snapshot, with no pulse.

| Problem | Safe response |
|---|---|
| Approved-tenant sign-in/access unavailable | Do not deploy elsewhere. Use repository walkthrough and discuss the architecture; label it non-live. |
| Source replication incomplete | Wait/check table status; do not relax validation or show stale totals as current. |
| Warehouse binding rejected | Inspect the native Warehouse item binding and permissions. A tested cloud SQL override is optional; do not create an empty pipeline as a substitute. |
| Ontology unavailable or graph unbound | Present the verified SQL/model/published-agent baseline. Explain the created schema and deferred graph/A-B acceptance. |
| Ontology context requests legacy `definition.json` | Disclose the preview format mismatch; do not publish an empty comparison agent or invent a compatibility part. |
| Agent unpublished, inaccurate, or preview unstable | Show independent Warehouse queries/model measures; do not claim agent accuracy. |
| Restricted test identity unavailable | Explain the control design and state access enforcement has not been demonstrated. |
| Not enough rehearsal time | Switch to a 20-minute SQL/mirroring/governance walkthrough or a discussion of source coexistence and evaluation. |

For baseline-only, require the first five checks and disclose that the ontology,
A/B comparison, and unperformed access checks are not part of the verified demo.
For full-demo claims, resolve every applicable unchecked item first.

After the full session, pause both capacities used:

```powershell
.\scripts\Set-FabricCapacityState.ps1 -State Suspend -Target All
```

For a primary-only rehearsal use `-Target Primary`; `-Target LegacyOntology`
controls the companion capacity, which now hosts both old and new ontology items.
Verify **Paused** in Azure. Pausing Fabric does not stop Azure SQL S3 or all storage
charges. Do not delete the source, workspace, private endpoint, or customer references.

## Product documentation

- [Ontology bindings](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-bind-data)
- [Ontology definition/export/update](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/ontology-definition)
- [Ontology context in Data Agent](https://learn.microsoft.com/en-us/fabric/data-science/data-agent-ontology-sources)
- [Data Agent evaluation](https://learn.microsoft.com/en-us/fabric/data-science/evaluate-data-agent)
- [Direct Lake behavior](https://learn.microsoft.com/en-us/fabric/fundamentals/direct-lake-how-it-works)
- [Warehouse pipeline connector](https://learn.microsoft.com/en-us/fabric/data-factory/connector-data-warehouse)
- [Fabric long-running operations](https://learn.microsoft.com/en-us/rest/api/fabric/articles/long-running-operation)
