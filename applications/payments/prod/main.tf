terraform {
  required_version = ">= 1.10"

  required_providers {
    conduktor = {
      source  = "conduktor/conduktor"
      version = "~> 1.5"
    }
  }

  backend "s3" {
    use_lockfile = true
  }
}

# Applied with this instance's ApplicationInstanceToken (CDK_API_KEY), which
# can only touch resources inside the ApplicationInstance's prefixes.
provider "conduktor" {
  mode = "console"
}

# Must match the cluster on the ApplicationInstance in platform/.
variable "cluster" {
  type    = string
  default = "kafka-prod"
}

variable "app_instance" {
  type    = string
  default = "payments-prod"
}
