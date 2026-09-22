terraform {
  required_version = ">= 1.10"

  required_providers {
    conduktor = {
      source  = "conduktor/conduktor"
      version = "~> 1.5"
    }
  }

  # Partial configuration -- bucket/key/region are supplied by CI from the
  # environment's CDK_STATE_REMOTE_URI. use_lockfile gives native S3 state
  # locking, so no DynamoDB table is required (Terraform >= 1.10).
  backend "s3" {
    use_lockfile = true
  }
}

# base_url and api_token are read from CDK_BASE_URL and CDK_API_KEY.
provider "conduktor" {
  mode = "console"
}
