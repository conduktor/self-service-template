# Conduktor Self-Service (Terraform)

Federated Kafka resource management via GitOps, using the [Conduktor Terraform provider](https://registry.terraform.io/providers/conduktor/conduktor/latest/docs). The **platform team** defines boundaries (applications, instances, policies); **application teams** take responsibility for their own Kafka resources within those boundaries through pull requests *without the need for approval from the platform team*.

In addition to mere GitOps automation for Kafka resources, Conduktor Self-Service unlocks:
- Enforceable and reusable guardrail policies to **enforce** best practices
- Reusable templates to **encourage** best practices
- Clear data ownership
- Data product discoverability and reusability
- Granular cost attribution / chargeback
- Efficient multi-tenancy through governance

> **Looking for the CLI version?** The `main` branch of this template manages the same resources with `conduktor apply` and YAML manifests. Pick that one unless you have a specific reason to want Terraform — see [Terraform vs. the Conduktor CLI](#terraform-vs-the-conduktor-cli) for an honest comparison.

## Key Concepts

Before diving in, understand the Conduktor self-service resource hierarchy. Each concept maps 1:1 to a Terraform resource:

| # | Concept | Terraform resource | Owner |
|---|---|---|---|
| 1 | [KafkaCluster](https://docs.conduktor.io/guide/reference/console-reference#kafkacluster) / [KafkaConnectCluster](https://docs.conduktor.io/guide/reference/console-reference#kafkaconnectcluster) -- Kafka and Kafka Connect endpoints that ApplicationInstances bind to | `conduktor_console_kafka_cluster_v2`, `conduktor_console_kafka_connect_v2` | Platform |
| 2 | [Group](https://docs.conduktor.io/guide/reference/console-reference#group) -- maps an external IdP group to Console, referenced as `spec.owner` on an Application | `conduktor_console_group_v2` | Platform |
| 3 | [Application](https://docs.conduktor.io/guide/reference/self-service-reference#application) -- a logical grouping representing a team or service | `conduktor_console_application_v1` | Platform |
| 4 | [ApplicationInstance](https://docs.conduktor.io/guide/reference/self-service-reference#applicationinstance) -- links an Application to a cluster/environment, defines ownership, creates the service account and permissions | `conduktor_console_application_instance_v1` | Platform |
| 5 | [ResourcePolicy](https://docs.conduktor.io/guide/reference/self-service-reference#resourcepolicy) -- CEL-based validation rules enforced at apply time | `conduktor_console_resource_policy_v1` | Platform |
| 6 | [ApplicationInstancePermission](https://docs.conduktor.io/guide/reference/self-service-reference#applicationinstancepermission) -- grants another application instance access to your topics | `conduktor_console_application_instance_permission_v1` | App team |
| 7 | [ApplicationGroup](https://docs.conduktor.io/guide/reference/self-service-reference#applicationgroup) -- Console UI permissions for team members within an application | `conduktor_console_application_group_v1` | App team |
| 8 | [Topic](https://docs.conduktor.io/guide/reference/kafka-reference#topic), [Subject](https://docs.conduktor.io/guide/reference/kafka-reference#subject), [Connector](https://docs.conduktor.io/guide/reference/kafka-reference#connector) -- the Kafka resources teams manage day-to-day | `conduktor_console_topic_v2`, `conduktor_console_kafka_subject_v2`, `conduktor_console_connector_v2` | App team |

Platform team resources are managed exclusively by the platform team. Application teams manage their own Kafka resources within the boundaries the platform team has defined.

> **Note on terminology:** `Group` and `ApplicationGroup` are distinct. A `Group` is a platform-managed resource granting UI permissions to a set of users; an `ApplicationGroup` is an app-managed resource granting UI permissions scoped within the application.

## Repository Structure

Terraform does not recurse into subdirectories, so **each state boundary is its own root module** -- a directory containing its own backend, provider and resources, applied independently.

```
conduktor-self-service/
├── .github/
│   ├── CODEOWNERS
│   └── workflows/
│       ├── apply-platform.yml      # AdminToken -- platform resources (excl. clusters)
│       ├── apply-clusters.yml      # AdminToken -- cluster resources, scoped per instance
│       └── apply-apps.yml          # ApplicationInstanceToken -- scoped per app/instance
├── applications/                   # App-managed resources (each team owns their folder)
│   └── <app>/
│       └── <instance>/             # ← root module
│           ├── main.tf             # backend, provider, cluster/instance variables
│           ├── topics.tf
│           ├── subjects.tf
│           ├── connectors.tf
│           ├── application-groups.tf       # Grant UI permissions
│           └── instance-permissions.tf     # Grant access to another application
├── platform/                       # ← root module (platform team resources only)
│   ├── main.tf                     # backend, provider
│   ├── groups.tf                   # Console Groups (map external IdP groups → Console)
│   ├── policies.tf                 # ResourcePolicy rules
│   ├── application-<app>.tf        # Application + ApplicationInstance per app
│   ├── exceptions.tf               # Policy exception overrides (AdminToken bypasses policies)
│   └── clusters/
│       └── <instance>/             # ← root module, applied with instance-scoped credentials
│           ├── main.tf
│           ├── variables.tf
│           └── kafka-<instance>.tf
├── scripts/
│   └── plan-to-manifests.py        # Renders a plan into manifests for the PR policy check
└── README.md
```

| Root module | Owner | Token Type | Purpose |
|---|---|---|---|
| `platform/` | Platform team | AdminToken | Applications, ApplicationInstances, Groups, ResourcePolicies, exceptions |
| `platform/clusters/<instance>/` | Platform team | AdminToken | KafkaCluster / KafkaConnectCluster per instance |
| `applications/<app>/<instance>/` | Application team | ApplicationInstanceToken | Day-to-day Kafka resources |

**Why `platform/` is flat.** `platform/groups.tf`, `policies.tf` and `application-<app>.tf` were separate directories in the CLI version. They are one root module here because the CLI applied them together under one state; splitting them would fragment that state for no benefit. `platform/clusters/<instance>/` stays nested because it always had its own state and credentials. Nested root modules are fine -- Terraform only reads the directory it is invoked from.

**About the `<instance>` folder slot:** an `<instance>` folder corresponds 1:1 to a Self-Service `ApplicationInstance`. Each maps to a distinct Kafka cluster binding, service account, permission set, and (often) resource policy.
The repo ships with `dev` and `prod` as example instance names, but `dev`/`stag`/`prod` is only the most familiar axis. Other dimensions that often warrant their own application instance:
- **Region / data residency** -- `prod-us-east`, `prod-eu-west`, `prod-ap-south` (latency, active-active DR, or laws that pin data to a region)
- **Data classification** -- `pii` vs `non-pii`, where PII workloads land on a cluster with tighter ACLs and encryption
- **Regulatory domain** -- `sox`, `pci`, `hipaa` -- different audit/retention rules even within prod
- **Workload tier** -- `critical`, `batch`, `analytics` -- dedicated clusters for mission-critical streaming vs. shared infrastructure for bulk/analytics
- **Tenant** (for multi-tenant apps) -- `tenant-acme`, `tenant-globex` -- isolation for noisy-neighbor, billing, or contractual reasons
- **Cluster migration** -- `legacy` vs `next-gen` -- temporary split during an upgrade or vendor swap

## How CI/CD Works

- **Pull requests** run `terraform plan`. For application resources they additionally run a **policy check** (see below).
- **Merges to main** run `terraform apply`. Three workflows split the work by scope:
  - `apply-platform.yml` -- AdminToken, `platform` GitHub Environment, root module `platform/`.
  - `apply-clusters.yml` -- AdminToken, per-instance GitHub Environments (e.g. `kafka-dev`, `kafka-prod`). Detects the changed `platform/clusters/<instance>/` folder and selects the matching environment so cluster credentials resolve correctly. Changes must be scoped to a single instance per PR.
  - `apply-apps.yml` -- ApplicationInstanceToken, detects the changed `<app>/<instance>` folder and selects the matching GitHub Environment for a scoped token. Changes must be scoped to a single `<app>/<instance>` per PR.
- **Policy exceptions** go in `platform/exceptions.tf`. That module applies with an AdminToken, and Console skips ResourcePolicy validation for admin tokens. Application teams open the PR; only the platform team can approve (CODEOWNERS).
- **State management** is native. Resources removed from `.tf` files are destroyed on the next apply -- there is no `--enable-state` flag to set.

### The PR policy check

**`terraform plan` cannot catch ResourcePolicy violations.** Conduktor evaluates CEL rules server-side when a resource is written; `plan` only diffs your config against state and never asks Console whether the resource would be accepted. A topic with 50 partitions plans perfectly cleanly against a policy that caps it at 3.

Left alone, that would move policy failures from "PR is red" to "main is red and Console is out of sync" -- losing the guardrail that is the point of Self-Service. So `apply-apps.yml` adds a step:

```bash
terraform show -json tfplan > plan.json
scripts/plan-to-manifests.py plan.json > manifests.yml
conduktor apply -f manifests.yml --dry-run     # real server-side CEL evaluation
```

`plan-to-manifests.py` extracts the four kinds that ResourcePolicies can target (Topic, Subject, Connector, ApplicationGroup) from the plan and renders them as Conduktor manifests. The dry-run returns the real policy verdict, exiting non-zero with the offending policy name and error message:

```
Could not apply resource Topic/payments.transactions: Policies check failed:
- topic-rules-dev: Partition count has to be between 1 and 3
```

The platform workflows deliberately have **no** such step: they apply with an AdminToken, which bypasses ResourcePolicy anyway.

### State Isolation

State isolation applies to **every** root module. The `platform`, each `kafka-<instance>`, and each `<app>-<instance>` GitHub Environment carries its own `CDK_STATE_REMOTE_URI` (a distinct S3 prefix) and its own `AWS_ROLE_ARN` (an IAM role scoped to that prefix). One workflow's state cannot be read or written by another.

The workflows use GitHub OIDC federation (`aws-actions/configure-aws-credentials` with `role-to-assume`) -- no static AWS keys. Each IAM role's trust policy is pinned to its corresponding GitHub Environment.

The S3 backend uses `use_lockfile = true` for native state locking, so **no DynamoDB table is required** (Terraform >= 1.10). CI parses `CDK_STATE_REMOTE_URI` into the backend's `bucket` and `key` at `terraform init` time via `-backend-config`, which is why the `backend "s3"` blocks in this repo are intentionally near-empty.

**Cross-boundary references are literal strings, not remote state.** An ApplicationInstance names its cluster as `cluster = "kafka-dev"`, not via a `terraform_remote_state` data source. This is deliberate: a data source would require every application team's IAM role to have read access to the platform state, undermining the isolation above. The cost is that renaming a cluster requires a matching edit in the modules that reference it.

## Onboarding

### Platform bootstrap (one-time)

1. Create `platform/clusters/<instance>/` for each Kafka cluster the platform will manage. Credentials come from GH Environment secrets as `TF_VAR_*` -- see `variables.tf`.
2. Add Console `Group` resources to `platform/groups.tf`, one per external IdP group. These are referenced by Applications via `spec.owner`.
3. Seed `platform/policies.tf` with the ResourcePolicies you want enforced. A default set ships with this repo (see "Included Resource Policies" below).
4. Create an S3 bucket for Terraform state, plus one IAM role per boundary scoped to its prefix, each with an OIDC trust policy pinned to its GitHub Environment.
5. Create the `platform` GitHub Environment with:
   - `CDK_API_KEY` (secret) -- AdminToken
   - `CDK_BASE_URL` (variable) -- Console URL
   - `CDK_STATE_REMOTE_URI` (variable) -- e.g., `s3://conduktor-state/platform/`
   - `AWS_ROLE_ARN` (variable) -- IAM role scoped to the platform state prefix
6. Create a `kafka-<instance>` GitHub Environment for each cluster instance (at minimum `kafka-dev`, `kafka-prod`) with:
   - `CDK_API_KEY`, `CDK_BASE_URL`, `CDK_STATE_REMOTE_URI`, `AWS_ROLE_ARN` as above, scoped to that instance
   - Cluster credential secrets: `KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_CREDENTIALS`, `SR_USER`, `SR_PASSWORD`, `KAFKA_CONNECT_URL`, `KAFKA_CONNECT_USERNAME`, `KAFKA_CONNECT_PASSWORD`

### Onboard a new application

#### Platform team

1. Create `platform/application-<app>.tf` with the `conduktor_console_application_v1` (its `spec.owner` referencing a Group) and one `conduktor_console_application_instance_v1` per instance. Topic/Connector/Subject policies go in the instance's `policy_ref`; ApplicationGroup policies go on the Application
2. Create an IAM role per app/instance scoped to its state prefix (e.g. `s3://conduktor-state/<app>/<instance>/`), with OIDC trust pinned to the GitHub Environment
3. Create GitHub Environments (`<app>-<instance>`) with:
   - `CDK_API_KEY` (secret) -- ApplicationInstanceToken, from `conduktor token create application-instance -i <instance> <name>`
   - `CDK_BASE_URL` (variable) -- Console URL
   - `CDK_STATE_REMOTE_URI` (variable) -- e.g., `s3://conduktor-state/<app>/<instance>/`
   - `AWS_ROLE_ARN` (variable) -- the IAM role from step 2
4. Scaffold `applications/<app>/<instance>/main.tf` (copy from `applications/payments/dev/main.tf`, adjusting the `cluster` and `app_instance` defaults)
5. Add CODEOWNERS entry: `/applications/<app>/  @org/<app>-team @org/platform-team`
6. Grant the team repo write access

#### Application team

1. Add [Topics](https://docs.conduktor.io/guide/reference/kafka-reference#topic) to `applications/<app>/<instance>/topics.tf`, matching the ApplicationInstance resource prefix (also [Subjects](https://docs.conduktor.io/guide/reference/kafka-reference#subject) and [Connectors](https://docs.conduktor.io/guide/reference/kafka-reference#connector) as needed)
2. Add `application-groups.tf` to set up Console UI permissions
3. Add `instance-permissions.tf` if cross-team topic access is needed
4. Open a PR -- `terraform plan` plus the dry-run policy check validate the change. After review and merge, resources apply automatically.

No workflow changes needed -- the detection logic handles new applications automatically.

## Working Locally

```bash
export CDK_BASE_URL="https://console.example.com"
export CDK_API_KEY="<your token>"

cd applications/payments/dev
terraform init -backend=false      # skip remote state for a local syntax check
terraform validate
terraform fmt -check -recursive
```

To plan against real state you need the backend config and AWS credentials that CI uses; in practice, let the PR do it.

## Labels Convention

| Label | Purpose | Example |
|---|---|---|
| `instance` | ApplicationInstance identifier | `dev`, `stag`, `prod` |
| `business-unit` | Organizational grouping | `finance`, `risk`, `logistics` |
| `confidentiality` | Data classification | `public`, `internal`, `restricted` |
| `team` | Owning team | `payments-owners` |

## Included Resource Policies

| Policy | Target | Description |
|---|---|---|
| `topic-naming` | Topic | Enforces `<app>.<descriptive-name>` naming |
| `topic-labels` | Topic | Requires `instance`, `business-unit`, `confidentiality`, `team` labels |
| `topic-rules-dev` | Topic | Dev instance rules (RF = 3, partitions 1-3) |
| `topic-rules-prod` | Topic | Strict rules for prod (RF = 3, partitions <= 12, retention >= 1h, ISR >= 2) |
| `subject-rules` | Subject | Requires `-key` or `-value` suffix, explicit compatibility |
| `connector-rules` | Connector | Restricts plugin classes, tasks.max <= 8 |
| `appgroup-restrictions` | ApplicationGroup | No direct members, read-only prod topic access |

CEL conditions are written as HCL heredocs. HCL heredocs do not process backslash escapes, so regex escaping (`\\.`) carries over from the YAML form verbatim.

**Where each policy attaches.** An ApplicationInstance's `policy_ref` accepts only `Topic`, `Connector` and `Subject` policies -- naming an `ApplicationGroup` policy there is rejected with `Policy with name '<name>' has ApplicationGroup but only [Connector, Topic, Subject] are allowed`. `appgroup-restrictions` is therefore referenced from the `conduktor_console_application_v1` resource, where it covers every instance of the application. `ApplicationInstancePermission` policies are cluster scoped and attach through a KafkaCluster's `policies_ref`.

## Terraform vs. the Conduktor CLI

Both approaches manage the same Console resources. Choose deliberately:

| | Terraform (this branch) | Conduktor CLI (`main`) |
|---|---|---|
| Pre-merge policy feedback | Requires the extra dry-run step in `apply-apps.yml` | Native -- `conduktor apply --dry-run` |
| State | Terraform state in S3, one per boundary | `--enable-state` with a remote URI per boundary |
| Drift detection | `terraform plan` shows drift from real Console state | Not available |
| Deletion on removal | Native | `--enable-state` |
| Resource coverage | Every kind this repo uses has a typed resource; anything newer needs `conduktor_generic` | Whatever the API supports, immediately |
| Fits existing IaC | Plans alongside your other Terraform | Separate tool in the pipeline |

Pick Terraform if your organisation already standardises on it and values drift detection. Pick the CLI if you want the simplest pipeline and native policy dry-runs.

## Repository Layout Options

This repo co-locates platform resources and application resources in a single repository. That's one of a few reasonable layouts -- a monorepo makes policy enforcement, CODEOWNERS-based review, and cross-team changes easy to see in one place. Other teams split platform and application resources across separate repositories along organizational boundaries. The resource model and workflows work the same way either way; splitting repos just means duplicating the CI/CD wiring on the application side.

## Note on Deployment

This repo only governs objects within the Conduktor [Console](https://docs.conduktor.io/guide/reference/console-reference), [Self-Service](https://docs.conduktor.io/guide/reference/self-service-reference), and [Kafka Resource](https://docs.conduktor.io/guide/reference/kafka-reference) APIs. It does not concern itself with configuration and deployment of Conduktor Console itself.

For the sake of simplicity this repo doesn't include objects from the [Conduktor Gateway API](https://docs.conduktor.io/guide/reference/gateway-reference), but can be extended to do so -- the provider ships `conduktor_gateway_*` resources. Managing both Console and Gateway in one root module requires two `provider` blocks with `alias` and `mode = "gateway"` on the second.

As an alternative to Terraform, the [Conduktor Provisioner helm chart](https://github.com/conduktor/conduktor-public-charts/tree/main/charts/provisioner) runs the Conduktor CLI from a pod in Kubernetes -- helpful if networking restrictions prevent CI runners from reaching the API endpoint directly.

To actually configure and deploy Conduktor Console itself, we recommend the [official Conduktor Console Kubernetes helm chart](https://github.com/conduktor/conduktor-public-charts/tree/main/charts/console). See the official [Conduktor Reference Architecture Console helm values](https://github.com/conduktor/conduktor-reference-architecture/blob/main/local-stack/console-values.yaml) for a production-ready Console deployment configuration example.
