# Policy exceptions.
#
# This root module applies with an AdminToken, and Console skips ResourcePolicy
# validation for admin tokens. A resource defined here therefore bypasses the
# policies that would reject it in an application team's own root module.
#
# Application teams author the change; only the platform team can approve it
# (see .github/CODEOWNERS). Keep each exception commented with why it exists
# and when it should be removed.
#
# Because this is a separate Terraform state from applications/<app>/<instance>,
# an exception must not duplicate a resource that the app team's state already
# manages -- the two states would fight over it on every apply.
#
# Example: payments needs 24 partitions in prod, above the topic-rules-prod
# ceiling of 12. Approved 2026-09-22, revisit when the consumer is rebalanced.
#
# resource "conduktor_console_topic_v2" "payments_prod_highvolume" {
#   name    = "payments.highvolume"
#   cluster = "kafka-prod"
#   labels = {
#     instance        = "prod"
#     "business-unit" = "finance"
#     confidentiality = "restricted"
#     team            = "payments-team"
#   }
#   spec = {
#     partitions         = 24
#     replication_factor = 3
#     configs = {
#       "cleanup.policy"      = "delete"
#       "retention.ms"        = "604800000"
#       "min.insync.replicas" = "2"
#     }
#   }
# }
