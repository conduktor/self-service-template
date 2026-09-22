# Grant the support team permission to read prod data in the UI.
# appgroup-restrictions caps prod topic permissions at consume / view config /
# manage data quality -- adding topicProduce here is rejected at apply time.
resource "conduktor_console_application_group_v1" "payments_prod_readers" {
  name        = "payments-prod-readers"
  application = "payments"

  spec = {
    display_name = "Payments Prod Readers"
    description  = "Read-only access to payments production topics"

    members         = []
    external_groups = ["support-team"]

    permissions = [
      {
        app_instance  = var.app_instance
        resource_type = "TOPIC"
        pattern_type  = "LITERAL"
        name          = "*"
        permissions = [
          "topicViewConfig",
          "topicConsume",
        ]
      },
    ]
  }
}
