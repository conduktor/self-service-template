resource "conduktor_console_application_group_v1" "payments_dev_ui_permissions" {
  name        = "payments-dev-ui-permissions"
  application = "payments"

  spec = {
    display_name = "Payments Developers"
    description  = "Payments developers get full access to payments resources in dev environment"

    members         = [] # Use external_groups for IdP-managed membership
    external_groups = ["payments-devs"]

    permissions = [
      {
        app_instance  = var.app_instance
        resource_type = "TOPIC"
        pattern_type  = "LITERAL"
        # '*' is scoped to what this application instance owns
        name = "*"
        permissions = [
          "topicViewConfig",
          "topicConsume",
          "topicProduce",
          "topicEditConfig",
          "topicCreate",
          "topicDelete",
        ]
      },
    ]
  }
}
