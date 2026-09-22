resource "conduktor_console_kafka_cluster_v2" "kafka_dev" {
  name = "kafka-dev"
  spec = {
    display_name                 = "Dev kafka cluster"
    icon                         = "kafka"
    color                        = "#000000"
    bootstrap_servers            = var.kafka_bootstrap_servers
    ignore_untrusted_certificate = false

    properties = {
      "sasl.jaas.config"  = var.kafka_credentials
      "security.protocol" = "SASL_SSL"
      "sasl.mechanism"    = "PLAIN"
    }

    # YAML's `schemaRegistry.type: ConfluentLike` becomes a typed block.
    schema_registry = {
      confluent_like = {
        url                          = var.schema_registry_url
        ignore_untrusted_certificate = false
        security = {
          basic_auth = {
            username = var.sr_user
            password = var.sr_password
          }
        }
      }
    }
  }
}

resource "conduktor_console_kafka_connect_v2" "connect_dev" {
  name    = "connect-dev"
  cluster = conduktor_console_kafka_cluster_v2.kafka_dev.name
  spec = {
    display_name                 = "Dev Kafka Connect Cluster"
    urls                         = var.kafka_connect_url
    ignore_untrusted_certificate = false

    headers = {
      "X-PROJECT-HEADER" = "value"
      "AnotherHeader"    = "test"
    }

    security = {
      basic_auth = {
        username = var.kafka_connect_username
        password = var.kafka_connect_password
      }
    }
  }
}
