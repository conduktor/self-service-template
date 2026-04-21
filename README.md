# Conduktor Self-Service

Federated Kafka resource management via GitOps. The **platform team** defines boundaries (applications, instances, policies); **application teams** manage their own Kafka resources within those boundaries through pull requests.

## Key Concepts

Before diving in, understand the Conduktor self-service resource hierarchy:

1. **[Application](https://docs.conduktor.io/guide/reference/self-service-reference#application)** -- a logical grouping representing a team or service (admin resource)
2. **[ApplicationInstance](https://docs.conduktor.io/guide/reference/self-service-reference#applicationinstance)** -- links an Application to a specific Kafka cluster/environment, defines ownership, and creates service account and user permissions (admin resource)
3. **[ResourcePolicy](https://docs.conduktor.io/guide/reference/self-service-reference#resourcepolicy)** -- CEL-based validation rules enforced at apply time (admin resource)
4. **[ApplicationInstancePermission](https://docs.conduktor.io/guide/reference/self-service-reference#applicationinstancepermission)** -- grants another application instance access to your topics, enabling cross-team collaboration (app-managed resource)
5. **[ApplicationGroup](https://docs.conduktor.io/guide/reference/self-service-reference#applicationgroup)** -- defines Console UI permissions for team members within an application (app-managed resource)
6. **[Topic](https://docs.conduktor.io/guide/reference/kafka-reference#topic), [Subject](https://docs.conduktor.io/guide/reference/kafka-reference#subject), [Connector](https://docs.conduktor.io/guide/reference/kafka-reference#connector)** -- the actual Kafka resources teams manage day-to-day (app-managed resources)

Admin resources (`Application`, `ApplicationInstance`, `ResourcePolicy`) are managed exclusively by the platform team. Application teams manage their own Kafka resources within the boundaries the platform team has defined.

All resources follow a Kubernetes-style declarative format:

```yaml
apiVersion: self-serve/v1  # or kafka/v2 for Kafka resources
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
│       ├── apply-clusters.yml      # AdminToken -- cluster resources, scoped per env
│       └── apply-apps.yml          # ApplicationInstanceToken -- scoped per app/env
├── platform/                       # Admin resources (platform team only)
│   ├── applications/
│   │   └── <app>/
│   │       ├── application.yml     # Application resource
│   │       └── <env>.yml           # ApplicationInstance per environment
│   ├── clusters/                   # KafkaCluster / KafkaConnectCluster definitions
│   │   └── <env>/                  # Applied with env-scoped cluster credentials
│   ├── groups/                     # Console Groups (map external IdP groups -> Console)
│   ├── policies/                   # ResourcePolicy rules
│   └── exceptions/                 # Policy exception overrides
│       └── <app>/<env>/            # Applied with AdminToken to bypass policies
├── applications/                   # App-managed resources (each team owns their folder)
│   └── <app>/
│       └── <env>/
│           ├── topics.yml
│           ├── subjects.yml
│           ├── connectors.yml
│           ├── application-groups.yml
│           └── instance-permissions.yml
└── README.md
```

| Directory | Owner | Token Type | Purpose |
|---|---|---|---|
| `platform/applications/` | Platform team | AdminToken | Application and ApplicationInstance definitions |
| `platform/clusters/<env>/` | Platform team | AdminToken | KafkaCluster / KafkaConnectCluster definitions per environment |
| `platform/groups/` | Platform team | AdminToken | Console Groups mapped from external IdP groups |
| `platform/policies/` | Platform team | AdminToken | ResourcePolicy rules |
| `platform/exceptions/` | Platform team (approver), App team (author) | AdminToken | Policy exception overrides |
| `applications/<app>/<env>/` | Application team | ApplicationInstanceToken | Day-to-day Kafka resources |

## How CI/CD Works

- **Pull requests** run `conduktor apply --dry-run` against the live Console instance. Policy violations surface before merge.
- **Merges to main** apply resources automatically. Three workflows split the work by scope:
  - `apply-platform.yml` -- AdminToken, `platform` GitHub Environment, applies everything under `platform/` *except* `platform/clusters/`.
  - `apply-clusters.yml` -- AdminToken, per-env GitHub Environments (`kafka-dev`, `kafka-prod`). Detects the changed `platform/clusters/<env>/` folder and selects the matching environment so cluster credentials (`KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_CREDENTIALS`, Schema Registry, Kafka Connect) resolve correctly. Changes must be scoped to a single env per PR.
  - `apply-apps.yml` -- ApplicationInstanceToken, detects the changed `<app>/<env>` folder and selects the matching GitHub Environment for a scoped token.
- **Policy exceptions** go in `platform/exceptions/<app>/<env>/`. The platform workflow applies them with an AdminToken, bypassing policy validation. Application teams open the PR; only the platform team can approve (CODEOWNERS).
- **State management** is enabled via `--enable-state`. Resources removed from YAML are deleted from Conduktor on the next apply. Each app/env has an isolated state file (see State Isolation below).

### State Isolation

Each app/env gets its own remote state file and cloud IAM role. This prevents one application's workflow from reading or writing another application's state.

The workflows use GitHub OIDC federation (`aws-actions/configure-aws-credentials` with `role-to-assume`) -- no static AWS keys. Each GitHub Environment stores its own `AWS_ROLE_ARN`, and the IAM role trust policy is pinned to that environment.

## Onboard a New Application

### Platform team

1. Create `platform/applications/<app>/application.yml` (`spec.owner` -> Console Group)
2. Create `platform/applications/<app>/<env>.yml` per environment (ApplicationInstance with cluster, serviceAccount, policyRef, resources)
3. Create an IAM role per app/env scoped to its state prefix (e.g., `s3://conduktor-state/<app>/<env>/`), with OIDC trust pinned to the GitHub Environment
4. Create GitHub Environments (`<app>-<env>`) with:
   - `CDK_API_KEY` (secret) -- ApplicationInstanceToken
   - `CDK_BASE_URL` (variable) -- Console URL
   - `CDK_STATE_REMOTE_URI` (variable) -- e.g., `s3://conduktor-state/<app>/<env>/`
   - `AWS_ROLE_ARN` (variable) -- the IAM role from step 3
5. Add CODEOWNERS entry: `/applications/<app>/  @org/<app>-team @org/platform-team`
6. Grant the team repo write access

### Application team

1. Create `applications/<app>/<env>/topics.yml` with topics matching the ApplicationInstance resource prefix
2. Add `application-groups.yml` for Console UI permissions
3. Add `instance-permissions.yml` if cross-team topic access is needed
4. Open a PR -- dry-run validates against policies. After review and merge, resources apply automatically.

No workflow changes needed -- the detection logic handles new applications automatically.

## Labels Convention

| Label | Purpose | Example |
|---|---|---|
| `env` | Environment identifier | `dev`, `stag`, `prod` |
| `business-unit` | Organizational grouping | `finance`, `risk`, `logistics` |
| `confidentiality` | Data classification | `public`, `internal`, `restricted` |
| `team` | Owning team | `payments-team` |

## Included Policies

| Policy | Target | Description |
|---|---|---|
| `topic-naming` | Topic | Enforces `<app>.<descriptive-name>` naming |
| `topic-labels` | Topic | Requires `env`, `business-unit`, `confidentiality`, `team` labels |
| `topic-rules-dev` | Topic | Relaxed rules for dev (RF >= 1, partitions 1-3) |
| `topic-rules-prod` | Topic | Strict rules for prod (RF = 3, partitions <= 12, retention >= 1h, ISR >= 2) |
| `subject-rules` | Subject | Requires `-key` or `-value` suffix, explicit compatibility |
| `connector-rules` | Connector | Restricts plugin classes, tasks.max <= 8 |
| `appgroup-restrictions` | ApplicationGroup | No direct members, read-only prod topic access |

## Getting Started

1. Replace `my-kafka-cluster` in the YAML files with your actual Console cluster name
2. Replace `@org/platform-team` and `@org/payments-team` in CODEOWNERS with your GitHub org/team slugs
3. Set up GitHub Environments with the required secrets and variables (see Onboard a New Application)
4. Push to GitHub and enable branch protection on `main` with required reviews and CODEOWNERS enforcement

## Note on Deployment

This repo only governs objects within the Conduktor [Console](https://docs.conduktor.io/guide/reference/console-reference), [Self-Service](https://docs.conduktor.io/guide/reference/self-service-reference), and [Kafka Resource](https://docs.conduktor.io/guide/reference/kafka-reference) APIs.

Also note that for the sake of simplicity, this repo doesn't currently include objects from the [Conduktor Gateway API](https://docs.conduktor.io/guide/reference/gateway-reference) but can be easily extended to do so.

To configure and deploy Conduktor Console itself, we recommend to use the [official Conduktor Console Kubernetes helm chart](https://github.com/conduktor/conduktor-public-charts/tree/main/charts/console). See the official [Conduktor Reference Architecture Console helm values](https://github.com/conduktor/conduktor-reference-architecture/blob/main/local-stack/console-values.yaml) for a production-ready Console deployment configuration example.

As an alternative approach to implement Conduktor API resource gitops, you can use the [Conduktor Provisioner helm chart](https://github.com/conduktor/conduktor-public-charts/tree/main/charts/provisioner) to provision API object resources from within your Kubernetes cluster. This helm chart is sometimes helpful if networking restrictions prevent the CI runners from reaching the API endpoint directly. This helm chart basically just runs the Conduktor CLI from a pod in Kubernetes.
