# Uncomment and modify to grant another application instance access to your topics.
#
# resource "conduktor_console_application_instance_permission_v1" "allow_analytics_read" {
#   name         = "allow-analytics-read"
#   application  = "payments"
#   app_instance = var.app_instance
#
#   spec = {
#     resource = {
#       type         = "TOPIC"
#       name         = "payments.transactions"
#       pattern_type = "LITERAL"
#     }
#     service_account_permission = "READ"
#     user_permission            = "NONE"
#     granted_to                 = "analytics-dev" # The other team's ApplicationInstance name
#   }
# }
