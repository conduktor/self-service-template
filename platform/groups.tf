# Console Groups mirroring external IdP groups. Referenced by Applications
# via spec.owner, and by ApplicationGroups via spec.external_groups.

resource "conduktor_console_group_v2" "payments_owners" {
  name = "payments-owners"
  spec = {
    display_name    = "Payments"
    description     = "Group for the Payments owners"
    external_groups = ["payments-owners"]
  }
}

resource "conduktor_console_group_v2" "payments_devs" {
  name = "payments-devs"
  spec = {
    display_name    = "Payments"
    description     = "Group for the Payments developers"
    external_groups = ["payments-devs"]
  }
}

resource "conduktor_console_group_v2" "support_team" {
  name = "support-team"
  spec = {
    display_name    = "Support"
    description     = "Group for the Support team"
    external_groups = ["support-team"]
  }
}
