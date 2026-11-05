# Deployment summary

## Current status: published baseline verified; ontology runtime blocked

After signing in to the approved tenant, the guarded source initialization pipeline
completed, the paused mirror was resumed, and the five physical reporting tables
were created and populated. Direct Warehouse refresh and validation returned:

- 90,000 source / 70,944 reported appointments, 5,163 visible appointment groups.
- 12,000 reported referrals, 50% completed.
- Weighted wait of approximately 18.97 days.

The existing semantic model was updated to physical reporting tables and refreshed.
On November 5, all seven live DAX question-bank checks passed, including no-show
rate, longest-wait service, and September capacity snapshots. An earlier MSOLAP
connection error did not recur after resuming the capacities, which had been
found Paused. DirectQuery fallback was not enabled to obtain these results.

The actual analytics pipeline then completed with a native Warehouse item binding;
no separate SQL/OAuth cloud connection, new secret, or permission grant was needed.
Pipeline job `79c02f3b-7a7b-466a-b25c-87ddb39e7aca` and subsequent model refresh
`f6a953eb-18e0-4ac7-90ed-201007f8b1d3` completed successfully.

Agent A was published with three explicit selected reporting-model tables.
All seven natural-language known answers matched the same canonical fixture through
the actual published MCP endpoint, including the corrected explanation that 70,944
excludes upstream-suppressed groups. The model cannot infer omitted/source counts.
Four negative prompts disclosed no prohibited result; small-group and clinical
requests received generic service safety refusals rather than explanatory refusals.
This does not prove permissions or unrestricted agent accuracy.

### New ontology

- Name: `CCSF_Community_Health_Demo_Ontology`.
- Workspace: existing `ws-e2e-sql-to-fabricagent-iq`.
- ID: `08fc9ac6-3cce-463f-81d4-b177d6548d19`.
- Five entities, five backing tables, four relationships; 17 persisted definition
  parts retrieved and property/relationship declarations checked.
- [Open the ontology](https://app.fabric.microsoft.com/groups/2cd38c5e-ce17-4ce8-84ee-83aa55b34a2d/ontologies/08fc9ac6-3cce-463f-81d4-b177d6548d19?ctid=aa56606c-b0ba-43a8-9c11-eb0144a67efb).

The authenticated primary-workspace request returned `403 FeatureNotAvailable`;
the existing companion accepted creation. The legacy conceptual item was not
modified, and no new workspace or capacity was provisioned.

The editor now renders the five-entity/four-relationship schema. Manage graph
reports every entity Ineligible with "Unsupported Datasource". A new companion
Lakehouse `CommunityHealthOntologyLH` (`603910f1-cbcd-4abe-8ac1-fdaa3bb35511`) and five
native OneLake shortcuts to only the Warehouse reporting tables were tested.
The shortcuts registered as Delta tables, but graph execution was still not accepted.
No raw data was copied. The live ontology was subsequently restored to the
checked-in Warehouse/reporting source using the standalone redeployer, with all
17 parts read back. Native table/column/expression lineage tags are preserved.

Agent B draft `2fae1070-e269-467b-8b89-584d6bc6f0d5` was created. Its context service
rejected the new TMDL ontology because it expects a root `definition.json` part.
No context is attached and B is not published or accepted.

### Remaining acceptance

- Graph materialization/instance traversal and agent B are blocked by the specific
  preview failures above, not by an unresolved sign-in. Do not present an A/B win.
- Restricted-identity SQL/OneLake/model/published-agent permission checks are not run.
- Repeat the published baseline rehearsal before presenting; use the tested
  [native MCP runner](../scripts/Invoke-FabricDataAgent.ps1) on PowerShell 7.4+.
  The optional Python runner encountered intermittent transport connection timeouts;
  native HTTP/1.1 completed the same real requests.
- Use the [presenter runbook](presenter-runbook.md) go/no-go checklist and baseline fallback.
- No ARM infrastructure deployment or SQL administrator replacement ran.

## Revised implementation

| Layer | Checked-in change |
|---|---|
| Source | Additive schema; guarded, repeatable synthetic upserts; 90,000 appointments / 12,000 referrals |
| Warehouse | Transactional full refresh; five physical, governed reporting tables; nonempty/threshold/key/relationship checks |
| Model | Reporting-table Direct Lake partitions; weighted average wait; completion and capacity measures; no silent fallback |
| Pipeline | Actual Script activity, proven native Warehouse binding, bounded job polling |
| Ontology | New companion ontology, five entities/four backed declarations, stable native source lineage tags; graph not accepted |
| Agent | Explicit table selection, publication/read-back, native MCP runner; B format incompatibility disclosed |
| Validation | 29 Python / 29 mocked PowerShell checks; live SQL, seven DAX and seven published answers verified; ontology definition update/read-back verified |

Canonical reported appointments are **70,944**, excluding suppressed groups;
weighted wait is **1,345,727 / 70,944 days**; referrals are **12,000**, **50%** completed.
These are deliberately synthetic, locally and live-reproduced known answers, not customer findings.

## Historical deployment inventory, not current live state

The earlier deployment established a private Azure SQL -> mirroring -> Warehouse
-> semantic model -> Data Agent path. A subsequent audit found both privacy views
empty despite a passing check, an average-of-averages error, and an empty analytics
pipeline item. Therefore the old "validated end to end" claim was too broad.

| Resource/item | Historical name or ID |
|---|---|
| Approved tenant | `aa56606c-b0ba-43a8-9c11-eb0144a67efb` |
| Approved subscription | `d6721f8a-9863-4f84-b7e6-c6e857272fec` |
| Source resource group | `rg-e2e-sql-to-fabricagent` |
| Azure SQL server | `sql-e2e-fabricagent-dev-3af2`; private-only, Entra-only |
| Azure SQL database | `sqldb-community-health`; S3 / 100 DTU |
| VNet / vault | `vnet-e2e-fabricagent` / `kv-e2e-fabric-3af2` |
| Primary capacity | `fabriccapacitydemo001b`, West US 3 |
| Primary workspace | `ws-e2e-sql-to-fabricagent`; `09abc1c1-6e9f-4062-9c5f-be59d4300e12` |
| VNet gateway | `30e1ee2d-f9d4-4b9a-9240-678ea58b5276` |
| Private source connection | `a691b72e-6f04-4b87-a6c9-4827dc4a9bfa` |
| Source pipeline | `400a308d-ceae-49d6-82da-144da1f161df` |
| Mirror | `66474c57-5cf4-4930-82a8-6cdab5f8b4e6` |
| Warehouse | `a987c2d4-af3a-47c4-881d-9092d05e2c78` |
| Analytics pipeline item | `c12039f9-7d16-427a-8c0c-9d803f0ff68c` |
| Semantic model | `08d658a3-a6ce-4b13-a821-676486f297cb` |
| Data Agent | `cbc7c698-fa5b-4a48-bc51-9b80d6aca8d6` |
| Legacy companion workspace | `ws-e2e-sql-to-fabricagent-iq`, West US |
| Legacy capacity | `fabriccapacitydemo001` |
| Legacy conceptual ontology | `8c3edfcd-1792-4dca-a803-fb302b7fcfd0`; seven entities/six relationships, historically unbound |

The new ontology uses a distinct name and does not overwrite that historical item.
Current product documentation supports Warehouse and semantic-model binding; the
old Lakehouse/Eventhouse-only limitation should not be repeated as a general rule.
No new capacity or cross-region reassignment is part of the repair. The standalone
creation explicitly reused the existing companion after the primary rejected it.
No Power BI report has been authored.

## Credentials and cost

The historical dedicated service principal is `sp-e2e-sql-to-fabricagent`. Its
recorded credential expiration is April 6, 2027; verify actual validity and rotate
through the encrypted Fabric connection. No credential is checked in or retrieved
when reusing the existing connection.

Both capacities were found Paused before final model verification, briefly resumed,
then **verified Paused again** at handoff on November 5. Resume both before the full
rehearsal and pause them after use; Azure SQL and some storage continue to incur cost.
No commits or pushes are performed by the repair.
