resource "conduktor_console_topic_v2" "payments_transactions" {
  name    = "payments.transactions"
  cluster = var.cluster

  labels = {
    instance        = "prod"
    "business-unit" = "finance"
    confidentiality = "restricted"
    team            = "payments-team"
  }

  spec = {
    partitions         = 6
    replication_factor = 3
    configs = {
      "cleanup.policy"      = "delete"
      "retention.ms"        = "604800000" # 7 days
      "min.insync.replicas" = "2"
    }
  }
}
