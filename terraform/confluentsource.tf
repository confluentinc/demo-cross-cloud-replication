data "confluent_organization" "my_org" {}

resource "random_id" "env_display_id" {
  byte_length = 4
}

# ------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------

resource "confluent_environment" "sourceenv" {
  display_name = "source-environment-${random_id.env_display_id.hex}"
  stream_governance {
    package = "ADVANCED"
  }
}

data "confluent_schema_registry_cluster" "sourcesr" {
  environment {
    id = confluent_environment.sourceenv.id
  }
  depends_on = [
    confluent_kafka_cluster.sourcecluster
  ]
}

# ------------------------------------------------------
# KAFKA Cluster, Attachement and Connection
# ------------------------------------------------------

resource "confluent_kafka_cluster" "sourcecluster" {
  display_name = "source-cluster"
  availability = "MULTI_ZONE"
  cloud        = "AWS"
  region       = var.aws_region
  enterprise {}
  environment {
    id = confluent_environment.sourceenv.id
  }
}

resource "confluent_private_link_attachment" "sourcepla" {
  cloud        = "AWS"
  region       = var.aws_region
  display_name = "${var.prefix}-source-aws-platt-${random_id.env_display_id.hex}"
  environment {
    id = confluent_environment.sourceenv.id
  }
}

resource "confluent_private_link_attachment_connection" "sourceplac" {
  display_name = "${var.prefix}-source-aws-plattc-${random_id.env_display_id.hex}"
  environment {
    id = confluent_environment.sourceenv.id
  }
  aws {
    vpc_endpoint_id = aws_vpc_endpoint.privatelink.id
  }

  private_link_attachment {
    id = confluent_private_link_attachment.sourcepla.id
  }
}

# ------------------------------------------------------
# SERVICE ACCOUNTS
# ------------------------------------------------------

resource "confluent_service_account" "app-manager" {
  display_name = "source-app-manager-${random_id.env_display_id.hex}"
  description  = "Service account to manage source Kafka cluster"
}

# ------------------------------------------------------
# ROLE BINDINGS
# ------------------------------------------------------

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.sourceenv.resource_name  
}

resource "confluent_role_binding" "app-manager-orgadmin-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "OrganizationAdmin"
  crn_pattern = data.confluent_organization.my_org.resource_name
}

# ------------------------------------------------------
# SCHEMA REGISTRY API KEYS
# ------------------------------------------------------

resource "confluent_api_key" "schema-registry-api-key" {
  display_name = "env-manager-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'env-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }
  managed_resource {
    id          = data.confluent_schema_registry_cluster.sourcesr.id
    api_version = data.confluent_schema_registry_cluster.sourcesr.api_version
    kind        = data.confluent_schema_registry_cluster.sourcesr.kind
    environment {
      id = confluent_environment.sourceenv.id
    }
  }
}

# ------------------------------------------------------
# KAFKA API KEY
# ------------------------------------------------------

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name           = "${var.prefix}-app-manager-kafka-api-key-${random_id.env_display_id.hex}"
  description            = "Kafka API Key that is owned by 'app-manager' service account"
  disable_wait_for_ready = true

  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.sourcecluster.id
    api_version = confluent_kafka_cluster.sourcecluster.api_version
    kind        = confluent_kafka_cluster.sourcecluster.kind

    environment {
      id = confluent_environment.sourceenv.id
    }
  }

  lifecycle {
    prevent_destroy = false # This is for development
  }
}
