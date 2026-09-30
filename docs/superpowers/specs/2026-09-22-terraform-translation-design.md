# Terraform translation of the Conduktor Self-Service template

**Date:** 2026-09-22
**Branch:** `chuck/terraform-provider`
**Status:** Implemented (policy gate revised 2026-09-30)

## Goal

Replace the Conduktor CLI + YAML implementation of this template with the
[Conduktor Terraform provider](https://registry.terraform.io/providers/conduktor/conduktor/latest/docs),
preserving the delegation model: platform teams define boundaries, application
teams manage resources inside them, and policy violations are caught before
merge.

Full replacement, not a parallel tree -- two sources of truth for the same
Console resources would be worse than either alone.

## Decisions

### 1. One root module per state boundary

Terraform does not recurse into subdirectories, so each boundary that had its
own CLI state and token becomes its own root module:

| Root module | Token | State key |
|---|---|---|
| `platform/` | Admin | `platform/` |
| `platform/clusters/<instance>/` | Admin | `kafka-<instance>/` |
| `applications/<app>/<instance>/` | ApplicationInstance | `<app>/<instance>/` |

Rejected: a single root module. It gives a real dependency graph and the
simplest HCL, but collapses token scoping -- every applier would need write
access to all state, defeating the delegation model this template exists for.

`platform/` is flattened (`groups.tf`, `policies.tf`, `application-<app>.tf`,
`exceptions.tf`) because the CLI applied those directories under one state.
`platform/clusters/<instance>/` stays nested; it always had its own state.

### 2. Cross-boundary references are literal strings

`cluster = "kafka-dev"`, not a `terraform_remote_state` data source. A data
source would require every application team's IAM role to read platform state,
undermining the isolation the boundaries exist to provide. Cost: renaming a
cluster requires a matching edit in referencing modules.

### 3. Secrets via `TF_VAR_*`

The CLI interpolated `${KAFKA_BOOTSTRAP_SERVERS}` into YAML. Terraform uses
`variable` blocks marked `sensitive`, fed from the same GitHub Environment
secrets as `TF_VAR_*`. **No new secrets are required.**

Provider auth needs no HCL: `CDK_BASE_URL` and `CDK_API_KEY` are already the
provider's native env vars, so every root module carries only
`provider "conduktor" { mode = "console" }`.

### 4. S3 backend with native locking

`use_lockfile = true` (Terraform >= 1.10) -- no DynamoDB table. Backend config
is partial; CI parses each environment's existing `CDK_STATE_REMOTE_URI` into
`-backend-config=bucket=… -backend-config=key=…`. Same variable, same OIDC
role, same isolation guarantee. `--enable-state` disappears; deletion on
removal is native.

### 5. Policy gate: apply on PR approval

The central problem. `terraform plan` is client-side -- it diffs config against
state and never asks Console whether a resource would be accepted. Conduktor
evaluates ResourcePolicy CEL rules server-side on write. So plan is green on a
resource that apply will reject.

`apply-apps.yml` therefore applies on `pull_request_review` (state `approved`)
instead of on merge. A policy violation fails the apply while the PR is still
open. On merge, it runs `terraform plan -detailed-exitcode` as a drift check
rather than applying again.

Platform and cluster workflows keep apply-on-merge: they use an AdminToken,
which bypasses ResourcePolicy, so applying earlier would catch nothing and only
add drift risk.

Accepted costs, each mitigated in the README by required branch protection:
Console can hold changes from a PR that was approved and then closed
unmerged; commits pushed after approval could merge unapplied (mitigated by
dismissing stale approvals); a policy failure leaves a PR partially applied;
and any approver with write access triggers the apply (restrict with
Environment required reviewers).

Considered and rejected:

- **Render the plan to Conduktor manifests and `conduktor apply --dry-run`
  them** (this branch's first implementation, 2026-09-22). It gives real
  server-side feedback with nothing written before merge, but adds a bespoke
  translation script that must track provider schema changes. Replaced
  2026-09-30 by apply-on-approval, which needs no extra machinery.
- **Mirror the CEL rules as Rego for Conftest.** The same rule would then live
  in two languages that can drift.

## Resource mapping

1:1 against provider v1.5.1; no `conduktor_generic` needed.

| YAML kind | Terraform resource |
|---|---|
| `KafkaCluster` | `conduktor_console_kafka_cluster_v2` |
| `KafkaConnectCluster` | `conduktor_console_kafka_connect_v2` |
| `Group` | `conduktor_console_group_v2` |
| `Application` | `conduktor_console_application_v1` |
| `ApplicationInstance` | `conduktor_console_application_instance_v1` |
| `ResourcePolicy` | `conduktor_console_resource_policy_v1` |
| `ApplicationGroup` | `conduktor_console_application_group_v1` |
| `ApplicationInstancePermission` | `conduktor_console_application_instance_permission_v1` |
| `Topic` | `conduktor_console_topic_v2` |

Shape changes: YAML's discriminated unions become typed blocks --
`schemaRegistry.type: ConfluentLike` → `schema_registry.confluent_like {}`,
`security.type: BasicAuth` → `security.basic_auth {}`. Topic `labels` move from
`metadata` to the top level.

CEL bodies are HCL heredocs. HCL heredocs do not process backslash escapes, so
regex escaping (`\\.`) carries over verbatim.

## Verification

Performed against a live Conduktor Console (Console 1.47.0, provider v1.5.1),
not inferred:

1. **All 5 root modules** pass `terraform validate` and `terraform fmt`.
2. **The full `platform/` module applies against live Console** -- 12 resources
   created, all 7 ResourcePolicies with CEL intact (verified by reading them
   back: `metadata.name.matches("^[a-z0-9-]+\\.[a-z0-9.-]+$")`).
3. **The policy gap is real.** With an ApplicationInstanceToken, a topic with
   50 partitions against `topic-rules-dev` (max 3):
   - `terraform plan` → clean, `Plan: 1 to add`
   - `conduktor apply --dry-run` → `Policies check failed: - topic-rules-dev: Partition count has to be between 1 and 3`
   - `terraform apply` → same failure
4. **Apply is where violations surface.** Item 3's `terraform apply` failure
   is the mechanism apply-on-approval relies on. It fails with the policy name
   and error message, so the failed check tells the PR author what to fix.
5. **ApplicationInstanceTokens can refresh.** `terraform plan` on existing state
   with an instance-scoped token returns `Refreshing state... No changes` --
   confirming per-app-instance root modules work with scoped tokens.

**Critical confounder, recorded because it invalidates naive testing:** an
**AdminToken bypasses ResourcePolicy entirely**. The 50-partition topic applies
cleanly with one. That is the documented mechanism behind `exceptions.tf`. Any
policy test using an admin token silently proves nothing.

## Not verified

- The GitHub Actions workflows have not run in CI. They are valid YAML with
  jobs, steps and env wiring checked programmatically, but backend-config
  parsing of `CDK_STATE_REMOTE_URI`, OIDC role assumption and the S3 backend
  itself are untested here -- no S3 bucket or GitHub Environment was involved.
- `subjects.tf` / `connectors.tf` are documented in the structure but not
  shipped as examples; the CLI template did not ship them either.
