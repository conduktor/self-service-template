# Application + ApplicationInstance definitions for the "payments" application.
# Onboarding a new application means adding one more file like this one.

resource "conduktor_console_application_v1" "payments" {
  name = "payments"
  spec = {
    title       = "Payments"
    description = "Payment processing service"
    owner       = conduktor_console_group_v2.payments_owners.name

    # ApplicationGroup policies attach here, not to an instance: an
    # ApplicationInstance's policy_ref accepts only Topic, Connector and
    # Subject policies.
    policy_ref = [conduktor_console_resource_policy_v1.appgroup_restrictions.name]
  }
}

resource "conduktor_console_application_instance_v1" "payments_dev" {
  name        = "payments-dev"
  application = conduktor_console_application_v1.payments.name
  spec = {
    # Cluster lives in the platform/clusters/<instance> state. Referenced by
    # name rather than via terraform_remote_state, so this module needs no
    # read access to another boundary's state.
    cluster         = "kafka-dev"
    service_account = "sa-payments-dev"

    policy_ref = [
      conduktor_console_resource_policy_v1.topic_naming.name,
      conduktor_console_resource_policy_v1.topic_labels.name,
      conduktor_console_resource_policy_v1.topic_rules_dev.name,
      conduktor_console_resource_policy_v1.subject_rules.name,
    ]

    default_catalog_visibility = "PUBLIC"

    resources = [
      { type = "TOPIC", pattern_type = "PREFIXED", name = "payments." },
      { type = "CONSUMER_GROUP", pattern_type = "PREFIXED", name = "payments." },
      { type = "SUBJECT", pattern_type = "PREFIXED", name = "payments." },
    ]
  }
}

resource "conduktor_console_application_instance_v1" "payments_prod" {
  name        = "payments-prod"
  application = conduktor_console_application_v1.payments.name
  spec = {
    cluster         = "kafka-prod"
    service_account = "sa-payments-prod"

    policy_ref = [
      conduktor_console_resource_policy_v1.topic_naming.name,
      conduktor_console_resource_policy_v1.topic_labels.name,
      conduktor_console_resource_policy_v1.topic_rules_prod.name,
      conduktor_console_resource_policy_v1.subject_rules.name,
    ]

    default_catalog_visibility = "PUBLIC"

    resources = [
      { type = "TOPIC", pattern_type = "PREFIXED", name = "payments." },
      { type = "CONSUMER_GROUP", pattern_type = "PREFIXED", name = "payments." },
      { type = "SUBJECT", pattern_type = "PREFIXED", name = "payments." },
    ]
  }
}
