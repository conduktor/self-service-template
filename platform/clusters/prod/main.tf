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

provider "conduktor" {
  mode = "console"
}
