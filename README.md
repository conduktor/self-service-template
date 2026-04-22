# Conduktor Self-Service

Federated Kafka resource management via GitOps. The **platform team** defines boundaries (applications, instances, policies); **application teams** manage their own Kafka resources within those boundaries through pull requests.

## Repository Layout Options

This repo co-locates platform resources and application resources in a single repository. That's one of a few reasonable layouts -- a monorepo makes policy enforcement, CODEOWNERS-based review, and cross-team changes easy to see in one place. Other teams split platform and application resources across separate repositories along organizational boundaries. The resource model and workflows work the same way either way; splitting repos just means duplicating the CI/CD wiring on the application side.

## Key Concepts

Before diving in, understand the Conduktor self-service resource hierarchy:

1. **[KafkaCluster](https://docs.conduktor.io/guide/reference/console-reference#kafkacluster) / [KafkaConnectCluster](https://docs.conduktor.io/guide/reference/console-reference#kafkaconnectcluster)** -- defines the Kafka and Kafka Connect endpoints (bootstrap servers, Schema Registry, credentials) that ApplicationInstances bind to (platform team resource)
2. **[Group](https://docs.conduktor.io/guide/reference/console-reference#group)** -- a Console Group, maps an external IdP group to Console and is referenced as `spec.owner` on an Application (platform team resource)
3. **[Application](https://docs.conduktor.io/guide/reference/self-service-reference#application)** -- a logical grouping representing a team or service (platform team resource)
4. **[ApplicationInstance](https://docs.conduktor.io/guide/reference/self-service-reference#applicationinstance)** -- links an Application to a specific Kafka cluster/environment, defines ownership, and creates service account and user permissions (platform team resource)
5. **[ResourcePolicy](https://docs.conduktor.io/guide/reference/self-service-reference#resourcepolicy)** -- CEL-based validation rules enforced at apply time (platform team resource)
6. **[ApplicationInstancePermission](https://docs.conduktor.io/guide/reference/self-service-reference#applicationinstancepermission)** -- grants another application instance access to your topics, enabling cross-team collaboration (app-managed resource)
7. **[ApplicationGroup](https://docs.conduktor.io/guide/reference/self-service-reference#applicationgroup)** -- defines Console UI permissions for team members within an application (app-managed resource)
8. **[Topic](https://docs.conduktor.io/guide/reference/kafka-reference#topic), [Subject](https://docs.conduktor.io/guide/reference/kafka-reference#subject), [Connector](https://docs.conduktor.io/guide/reference/kafka-reference#connector)** -- the actual Kafka resources teams manage day-to-day (app-managed resources)

Platform team resources (`KafkaCluster`, `KafkaConnectCluster`, `Group`, `Application`, `ApplicationInstance`, `ResourcePolicy`) are managed exclusively by the platform team. Application teams manage their own Kafka resources within the boundaries the platform team has defined.

> **Note on terminology:** `Group` (kind `Group`, `apiVersion: v2`) and `ApplicationGroup` (kind `ApplicationGroup`, `apiVersion: self-serve/v1`) are distinct resource kinds. A `Group` is a platform-managed Console Group that mirrors an external IdP group; an `ApplicationGroup` is an app-managed permission set that grants Console UI access to members of a `Group` within a specific Application.

All resources follow a Kubernetes-style declarative format:

```yaml
apiVersion: self-serve/v1   # Applications, ApplicationInstances, ResourcePolicies, ApplicationGroups
# also: kafka/v2 (Topics/Subjects/Connectors), console/v2 (Clusters), iam/v2 (Groups)
kind: <ResourceKind>
metadata:
  name: resource-name
  labels:
    key: value
spec:
  # Resource-specific fields
```

## Repository Structure

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
│       └── <instance>/
│           ├── topics.yml
│           ├── subjects.yml
│           ├── connectors.yml
│           ├── application-groups.yml       # Grant UI permissions
│           └── instance-permissions.yml     # Grant access to another application
├── platform/                       # Platform team resources only
│   ├── applications/
│   │   └── <app>/
│   │       ├── application.yml     # Application resource assigns ownership to Console Group
│   │       └── <instance>.yml      # ApplicationInstance per instance assigns permissions to a service account
│   ├── clusters/                   # KafkaCluster / KafkaConnectCluster definitions
│   │   └── <instance>/             # Applied with instance-scoped cluster credentials
│   ├── groups/                     # Console Groups (map external IdP groups -> Console)
│   ├── policies/                   # ResourcePolicy rules
│   └── exceptions/                 # Policy exception overrides
│       └── <app>/<instance>/       # Applied with AdminToken to bypass policies
└── README.md
```

| Directory | Owner | Token Type | Purpose |
|---|---|---|---|
| `platform/applications/` | Platform team | AdminToken | Application and ApplicationInstance definitions |
| `platform/clusters/<instance>/` | Platform team | AdminToken | KafkaCluster / KafkaConnectCluster definitions per instance |
| `platform/groups/` | Platform team | AdminToken | Console Groups mapped from external IdP groups |
| `platform/policies/` | Platform team | AdminToken | ResourcePolicy rules |
| `platform/exceptions/` | Platform team (approver), App team (author) | AdminToken | Policy exception overrides |
| `applications/<app>/<instance>/` | Application team | ApplicationInstanceToken | Day-to-day Kafka resources |

**About the `<instance>` folder slot:** Throughout this repo, an `<instance>` folder corresponds 1:1 to a Self-Service `ApplicationInstance`. Each application instance maps to a distinct Kafka cluster binding, service account, permission set, and (often) resource policy.
The repo ships with `dev` and `prod` as example instance names, but `dev`/`stag`/`prod` is only the most familiar axis. Other dimensions that often warrant their own application instance:
- **Region / data residency** -- `prod-us-east`, `prod-eu-west`, `prod-ap-south` (latency, active-active DR, or laws that pin data to a region)
- **Data classification** -- `pii` vs `non-pii`, where PII workloads land on a cluster with tighter ACLs and encryption
- **Regulatory domain** -- `sox`, `pci`, `hipaa` -- different audit/retention rules even within prod
- **Workload tier** -- `critical`, `batch`, `analytics` -- dedicated clusters for mission-critical streaming vs. shared infrastructure for bulk/analytics
- **Tenant** (for multi-tenant apps) -- `tenant-acme`, `tenant-globex` -- isolation for noisy-neighbor, billing, or contractual reasons
- **Cluster migration** -- `legacy` vs `next-gen` -- temporary split during an upgrade or vendor swap

## How CI/CD Works

- **Pull requests** run `conduktor apply --dry-run` against the live Console instance. Policy violations surface before merge.
- **Merges to main** apply resources automatically. Three workflows split the work by scope:
  - `apply-platform.yml` -- AdminToken, `platform` GitHub Environment, applies everything under `platform/` *except* `platform/clusters/`.
  - `apply-clusters.yml` -- AdminToken, per-instance GitHub Environments (e.g. `kafka-dev`, `kafka-prod`). Detects the changed `platform/clusters/<instance>/` folder and selects the matching environment so cluster credentials (`KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_CREDENTIALS`, Schema Registry, Kafka Connect) resolve correctly. Changes must be scoped to a single instance per PR.
  - `apply-apps.yml` -- ApplicationInstanceToken, detects the changed `<app>/<instance>` folder and selects the matching GitHub Environment for a scoped token. Changes must be scoped to a single `<app>/<instance>` per PR.
- **Policy exceptions** go in `platform/exceptions/<app>/<instance>/`. The platform workflow applies them with an AdminToken, bypassing policy validation. Application teams open the PR; only the platform team can approve (CODEOWNERS).
- **State management** is enabled via `--enable-state`. Resources removed from YAML are deleted from Conduktor on the next apply. Each app/instance has an isolated state file (see State Isolation below).

### State Isolation

State isolation applies to **every** workflow. The `platform`, each `kafka-<instance>`, and each `<app>-<instance>` GitHub Environment carries its own `CDK_STATE_REMOTE_URI` (a distinct remote state prefix) and its own `AWS_ROLE_ARN` (an IAM role scoped to that prefix). One workflow's state cannot be read or written by another.

The workflows use GitHub OIDC federation (`aws-actions/configure-aws-credentials` with `role-to-assume`) -- no static AWS keys. Each IAM role's trust policy is pinned to its corresponding GitHub Environment.

## Onboarding

### Platform bootstrap (one-time)

Before any application can be onboarded, the platform team sets up the shared infrastructure:

1. Create `platform/clusters/<instance>/*.yml` for each Kafka cluster and Kafka Connect cluster the platform will manage. Use the placeholder `${VAR}` syntax for credentials -- values come from GH Environment secrets at apply time.
2. Create `platform/groups/*.yml` for each Console `Group` that mirrors an external IdP group. These are referenced by Applications via `spec.owner`.
3. Seed `platform/policies/` with the ResourcePolicies you want enforced on topics, subjects, connectors, and application-groups. A default set ships with this repo (see "Included Resource Policies" below).
4. Create the `platform` GitHub Environment with:
   - `CDK_API_KEY` (secret) -- AdminToken
   - `CDK_BASE_URL` (variable) -- Console URL
   - `CDK_STATE_REMOTE_URI` (variable) -- e.g., `s3://conduktor-state/platform/`
   - `AWS_ROLE_ARN` (variable) -- IAM role scoped to the platform state prefix, OIDC trust pinned to this environment
5. Create a `kafka-<instance>` GitHub Environment for each cluster instance (at minimum `kafka-dev`, `kafka-prod`) with:
   - `CDK_API_KEY`, `CDK_BASE_URL`, `CDK_STATE_REMOTE_URI`, `AWS_ROLE_ARN` as above, scoped to that instance's state prefix and IAM role
   - Cluster credential secrets: `KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_CREDENTIALS`, `SR_USER`, `SR_PASSWORD`, `KAFKA_CONNECT_URL`, `KAFKA_CONNECT_USERNAME`, `KAFKA_CONNECT_PASSWORD`

### Onboard a new application

#### Platform team

1. Create `platform/applications/<app>/application.yml` (`spec.owner` -> Console Group)
2. Create `platform/applications/<app>/<instance>.yml` per instance (ApplicationInstance with cluster, serviceAccount, policyRef, resources)
3. Create an IAM role per app/instance scoped to its state prefix (e.g., `s3://conduktor-state/<app>/<instance>/`), with OIDC trust pinned to the GitHub Environment
4. Create GitHub Environments (`<app>-<instance>`) with:
   - `CDK_API_KEY` (secret) -- ApplicationInstanceToken
   - `CDK_BASE_URL` (variable) -- Console URL
   - `CDK_STATE_REMOTE_URI` (variable) -- e.g., `s3://conduktor-state/<app>/<instance>/`
   - `AWS_ROLE_ARN` (variable) -- the IAM role from step 3
5. Add CODEOWNERS entry: `/applications/<app>/  @org/<app>-team @org/platform-team`
6. Grant the team repo write access

#### Application team

1. Create `applications/<app>/<instance>/topics.yml` with [Topics](https://docs.conduktor.io/guide/reference/kafka-reference#topic) matching the ApplicationInstance resource prefix (also include [Subjects](https://docs.conduktor.io/guide/reference/kafka-reference#subject) and [Connectors](https://docs.conduktor.io/guide/reference/kafka-reference#connector) as needed)
2. Add `application-groups.yml` to set up Console UI permissions
3. Add `instance-permissions.yml` if cross-team topic access is needed
4. Open a PR -- dry-run validates against policies. After review and merge, resources apply automatically.

No workflow changes needed -- the detection logic handles new applications automatically.

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

## Getting Started

1. Adjust the shipped YAML files to match your Console environment:
   - `platform/clusters/<instance>/*.yml` -- set `metadata.name`, `spec.displayName`, `spec.bootstrapServers`, Schema Registry URL, Kafka Connect URL, and `policiesRef` (if any). Leave the `${VAR}` placeholders in place -- those are filled from GH Environment secrets at apply time.
   - `platform/groups/*.yml` -- set `metadata.name`, `spec.displayName`, and `spec.externalGroups` to match your IdP group names.
   - `platform/applications/<app>/*.yml` -- set `spec.owner` to a Console Group name, `spec.cluster` to a `KafkaCluster` name, and adjust `resources` prefixes to your naming convention.
2. Replace `@org/platform-team` and `@org/payments-owners` in CODEOWNERS with your GitHub org/team slugs.
3. Set up the `platform`, `kafka-<instance>`, and `<app>-<instance>` GitHub Environments with the required secrets and variables (see Platform bootstrap and Onboard a new application).
4. Push to GitHub and enable branch protection on `main` with required reviews and CODEOWNERS enforcement.

## Note on Deployment

This repo only governs objects within the Conduktor [Console](https://docs.conduktor.io/guide/reference/console-reference), [Self-Service](https://docs.conduktor.io/guide/reference/self-service-reference), and [Kafka Resource](https://docs.conduktor.io/guide/reference/kafka-reference) APIs. This repo does not concern itself with configuration and deployment of Conduktor Console itself.

Also note that for the sake of simplicity, this repo doesn't currently include objects from the [Conduktor Gateway API](https://docs.conduktor.io/guide/reference/gateway-reference) but can be easily extended to do so.

As an alternative approach to implement Conduktor API resource gitops, you can use the [Conduktor Provisioner helm chart](https://github.com/conduktor/conduktor-public-charts/tree/main/charts/provisioner) to provision API object resources from within your Kubernetes cluster. This helm chart is sometimes helpful if networking restrictions prevent the CI runners from reaching the API endpoint directly. It runs the Conduktor CLI from a pod in Kubernetes.

To actually configure and deploy Conduktor Console itself, we recommend the [official Conduktor Console Kubernetes helm chart](https://github.com/conduktor/conduktor-public-charts/tree/main/charts/console). See the official [Conduktor Reference Architecture Console helm values](https://github.com/conduktor/conduktor-reference-architecture/blob/main/local-stack/console-values.yaml) for a production-ready Console deployment configuration example.
