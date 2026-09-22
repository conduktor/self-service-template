resource "conduktor_console_topic_v2" "payments_transactions" {
  name    = "payments.transactions"
  cluster = var.cluster

  labels = {
    instance        = "dev"
    "business-unit" = "finance"
    confidentiality = "restricted"
    team            = "payments-team"
  }

  spec = {
    partitions         = 3
    replication_factor = 3
    configs = {
      "cleanup.policy" = "delete"
      "retention.ms"   = "86400000" # 1 day
    }
  }
}
