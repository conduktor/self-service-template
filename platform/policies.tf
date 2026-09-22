# ResourcePolicy CEL rules enforced by Console at write time.
#
# NOTE: `terraform plan` does NOT evaluate these -- Console applies them
# server-side on write, so violations surface at apply. The PR job runs
# `conduktor apply --dry-run` over the planned resources to restore
# pre-merge feedback. See README "How CI/CD Works".
#
# CEL bodies are written as heredocs: HCL heredocs do not process backslash
# escapes, so regex escaping (\\.) carries over from the YAML verbatim.

resource "conduktor_console_resource_policy_v1" "topic_naming" {
  name = "topic-naming"
  spec = {
    target_kind = "Topic"
    description = "Enforces topic naming convention"
    rules = [
      {
        condition     = <<-EOT
          metadata.name.matches("^[a-z0-9-]+\\.[a-z0-9.-]+$")
        EOT
        error_message = "Topic name must follow the pattern <app>.<descriptive-name>"
      },
    ]
  }
}

resource "conduktor_console_resource_policy_v1" "topic_labels" {
  name = "topic-labels"
  spec = {
    target_kind = "Topic"
    description = "Enforces required labels on topics"
    rules = [
      {
        condition     = <<-EOT
          has(metadata.labels.instance) && metadata.labels["instance"] in ["dev", "stag", "prod"]
        EOT
        error_message = "Topics must have an 'instance' label set to one of: dev, stag, prod"
      },
      {
        condition     = <<-EOT
          "business-unit" in metadata.labels
          && metadata.labels["business-unit"].size() > 0
        EOT
        error_message = "Topics must have a 'business-unit' label (e.g., finance, logistics, risk)"
      },
      {
        condition     = <<-EOT
          has(metadata.labels.confidentiality) && metadata.labels["confidentiality"] in ["public", "internal", "restricted"]
        EOT
        error_message = "Topics must have a 'confidentiality' label set to one of: public, internal, restricted"
      },
      {
        condition     = <<-EOT
          has(metadata.labels.team) && metadata.labels["team"].size() > 0
        EOT
        error_message = "Topics must have a 'team' label identifying the owning team"
      },
    ]
  }
}

resource "conduktor_console_resource_policy_v1" "topic_rules_dev" {
  name = "topic-rules-dev"
  spec = {
    target_kind = "Topic"
    description = "Topic rules for dev instances"
    rules = [
      {
        condition     = "spec.replicationFactor == 3"
        error_message = "Replication factor must be exactly 3"
      },
      {
        condition     = "spec.partitions >= 1 && spec.partitions <= 3"
        error_message = "Partition count has to be between 1 and 3"
      },
    ]
  }
}

resource "conduktor_console_resource_policy_v1" "topic_rules_prod" {
  name = "topic-rules-prod"
  spec = {
    target_kind = "Topic"
    description = "Strict topic rules for production environments"
    rules = [
      {
        condition     = "spec.replicationFactor == 3"
        error_message = "Replication factor has to be exactly 3 in production"
      },
      {
        condition     = "spec.partitions >= 1 && spec.partitions <= 12"
        error_message = "Production topics need less than or equal to 12 partitions. If you need an exception, plead your case to the platform team."
      },
      {
        condition     = <<-EOT
          "retention.ms" in spec.configs && int(string(spec.configs["retention.ms"])) >= 3600000
        EOT
        error_message = "Retention has to be explicitly set and at least 1 hour in production"
      },
      {
        condition     = <<-EOT
          "min.insync.replicas" in spec.configs && int(string(spec.configs["min.insync.replicas"])) >= 2
        EOT
        error_message = "min.insync.replicas has to be at least 2 in production"
      },
    ]
  }
}

resource "conduktor_console_resource_policy_v1" "subject_rules" {
  name = "subject-rules"
  spec = {
    target_kind = "Subject"
    description = "Enforces subject naming and compatibility standards"
    rules = [
      {
        condition     = <<-EOT
          metadata.name.matches("^[a-z0-9-]+\\.[a-z0-9.-]+-(?:key|value)$")
        EOT
        error_message = "Subject name must end with -key or -value suffix"
      },
      {
        condition     = <<-EOT
          has(spec.compatibility) && spec.compatibility in ["BACKWARD", "BACKWARD_TRANSITIVE", "FORWARD", "FORWARD_TRANSITIVE", "FULL", "FULL_TRANSITIVE"]
        EOT
        error_message = "Compatibility level has to be explicitly set and cannot be NONE"
      },
    ]
  }
}

resource "conduktor_console_resource_policy_v1" "connector_rules" {
  name = "connector-rules"
  spec = {
    target_kind = "Connector"
    description = "Restricts connector plugin classes and task limits"
    rules = [
      {
        condition     = <<-EOT
          spec.config["connector.class"] in [
            "io.connect.jdbc.JdbcSourceConnector",
            "io.connect.jdbc.JdbcSinkConnector",
            "io.debezium.connector.postgresql.PostgresConnector",
            "org.apache.kafka.connect.mirror.MirrorSourceConnector",
            "com.amazonaws.kafka.connect.s3.S3SinkConnector"
          ]
        EOT
        error_message = "Only approved connector classes are allowed -- contact the platform team to request a new class"
      },
      {
        condition     = <<-EOT
          int(spec.config["tasks.max"]) <= 8
        EOT
        error_message = "tasks.max cannot exceed 8"
      },
    ]
  }
}

resource "conduktor_console_resource_policy_v1" "appgroup_restrictions" {
  name = "appgroup-restrictions"
  spec = {
    target_kind = "ApplicationGroup"
    description = "Enforces group-based membership and restricts production permissions"
    rules = [
      {
        condition     = "!has(spec.members) || spec.members.size() == 0"
        error_message = "Direct user membership is not allowed -- use externalGroups to manage membership via your identity provider"
      },
      {
        condition     = <<-EOT
          spec.permissions
              .filter(p, p.appInstance.endsWith("-prod") && p.resourceType == "TOPIC")
              .all(p, p.permissions.all(perm, perm in ["topicConsume", "topicViewConfig", "topicDataQualityManage"]))
        EOT
        error_message = "For production topics, only consume, view config, and manage data quality are allowed"
      },
    ]
  }
}
