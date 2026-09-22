# Supplied by CI as TF_VAR_* from this instance's GitHub Environment secrets.
# These replace the ${VAR} placeholders the Conduktor CLI used to interpolate.

variable "kafka_bootstrap_servers" {
  type      = string
  sensitive = true
}

# Full JAAS config line, e.g.
# org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";
variable "kafka_credentials" {
  type      = string
  sensitive = true
}

variable "schema_registry_url" {
  type    = string
  default = "http://localhost:8080"
}

variable "sr_user" {
  type      = string
  sensitive = true
}

variable "sr_password" {
  type      = string
  sensitive = true
}

variable "kafka_connect_url" {
  type = string
}

variable "kafka_connect_username" {
  type      = string
  sensitive = true
}

variable "kafka_connect_password" {
  type      = string
  sensitive = true
}
