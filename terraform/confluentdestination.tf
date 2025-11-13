# ------------------------------------------------------
# REGION MAPPING
# ------------------------------------------------------
locals {
  azure_region_mapping = {
    # Azure Regions: User-friendly to programmatic names (based on Microsoft list) :contentReference[oaicite:1]{index=1}
    "East US"             = "eastus"
    "East US 2"           = "eastus2"
    "Central US"          = "centralus"
    "North Central US"    = "northcentralus"
    "South Central US"    = "southcentralus"
    "West US"             = "westus"
    "West US 2"           = "westus2"
    "West US 3"           = "westus3"
    "West Central US"     = "westcentralus"
    "Canada Central"      = "canadacentral"
    "Canada East"         = "canadaeast"
    "Brazil South"        = "brazilsouth"
    "Brazil Southeast"    = "brazilsoutheast"    
    "North Europe"        = "northeurope"
    "West Europe"         = "westeurope"
    "France Central"      = "francecentral"
    "France South"        = "francesouth"
    "Germany West Central"= "germanywestcentral"
    "Germany North"       = "germanynorth"       
    "Sweden Central"      = "swedencentral"
    "UK South"            = "uksouth"
    "UK West"             = "ukwest"
    "Norway East"         = "norwayeast"
    "Norway West"         = "norwaywest"          
    "Switzerland North"   = "switzerlandnorth"
    "Switzerland West"    = "switzerlandwest"
    "UAE North"           = "uaenorth"
    "UAE Central"         = "uaecentral"         
    "South Africa North"  = "southafricanorth"
    "South Africa West"   = "southafricawest"    
    "East Asia"           = "eastasia"
    "Southeast Asia"      = "southeastasia"
    "Japan East"          = "japaneast"
    "Japan West"          = "japanwest"
    "Korea Central"       = "koreacentral"
    "Korea South"         = "koreasouth"
    "Central India"       = "centralindia"
    "South India"         = "southindia"
    "West India"          = "westindia"
    "Australia East"      = "australiaeast"
    "Australia Southeast" = "australiasoutheast"
    "Australia Central"   = "australiacentral"
    "Australia Central 2" = "australiacentral2"
    "Chile Central"       = "chilecentral"       

    # Backward-compatible: programmatic names directly
    "eastus"            = "eastus"
    "eastus2"           = "eastus2"
    "centralus"         = "centralus"
    "northcentralus"    = "northcentralus"
    "southcentralus"    = "southcentralus"
    "westus"            = "westus"
    "westus2"           = "westus2"
    "westus3"           = "westus3"
    "westcentralus"     = "westcentralus"
    "canadacentral"     = "canadacentral"
    "canadaeast"        = "canadaeast"
    "brazilsouth"       = "brazilsouth"
    "brazilsoutheast"   = "brazilsoutheast"
    "northeurope"       = "northeurope"
    "westeurope"        = "westeurope"
    "francecentral"     = "francecentral"
    "francesouth"       = "francesouth"
    "germanywestcentral"= "germanywestcentral"
    "germanynorth"      = "germanynorth"
    "swedencentral"     = "swedencentral"
    "uksouth"           = "uksouth"
    "ukwest"            = "ukwest"
    "norwayeast"        = "norwayeast"
    "norwaywest"        = "norwaywest"
    "switzerlandnorth"  = "switzerlandnorth"
    "switzerlandwest"   = "switzerlandwest"
    "uaenorth"          = "uaenorth"
    "uaecentral"        = "uaecentral"
    "southafricanorth"  = "southafricanorth"
    "southafricawest"   = "southafricawest"
    "eastasia"          = "eastasia"
    "southeastasia"     = "southeastasia"
    "japaneast"         = "japaneast"
    "japanwest"         = "japanwest"
    "koreacentral"      = "koreacentral"
    "koreasouth"        = "koreasouth"
    "centralindia"      = "centralindia"
    "southindia"        = "southindia"
    "westindia"         = "westindia"
    "australiaeast"     = "australiaeast"
    "australiasoutheast"= "australiasoutheast"
    "australiacentral"  = "australiacentral"
    "australiacentral2" = "australiacentral2"
    "chilecentral"      = "chilecentral"
  }

  azure_confluent_region = lookup(local.azure_region_mapping, var.azure_region)

}

# ------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------

resource "confluent_environment" "destenv" {
  display_name = "PRIVATE-DESTINATION-AZURE"
  stream_governance {
    package = "ADVANCED"
  }
}

data "confluent_schema_registry_cluster" "destsr" {
  environment {
    id = confluent_environment.destenv.id
  }
  depends_on = [
    confluent_kafka_cluster.destcluster
  ]
}

# ------------------------------------------------------
# KAFKA Cluster, Attachement and Connection
# ------------------------------------------------------

resource "confluent_kafka_cluster" "destcluster" {
  display_name = "PRIVATE-DESTINATION-AZURE"
  availability = "MULTI_ZONE"
  cloud        = "AZURE"
  region       = local.azure_confluent_region
  enterprise {}
  environment {
    id = confluent_environment.destenv.id
  }
}

resource "confluent_private_link_attachment" "destpla" {
  cloud        = "AZURE"
  region       = local.azure_confluent_region
  display_name = "${var.prefix}-destination-azure-platt-${random_id.env_display_id.hex}"
  environment {
    id = confluent_environment.destenv.id
  }
}

resource "confluent_private_link_attachment_connection" "destplac" {
  display_name = "${var.prefix}-destination-azure-plattc-${random_id.env_display_id.hex}"
  environment {
    id = confluent_environment.destenv.id
  }
  azure {
    private_endpoint_resource_id = azurerm_private_endpoint.endpoint.id
  }

  private_link_attachment {
    id = confluent_private_link_attachment.destpla.id
  }
}

# ------------------------------------------------------
# SERVICE ACCOUNTS
# ------------------------------------------------------

resource "confluent_service_account" "dest-app-manager" {
  display_name = "destination-app-manager-${random_id.env_display_id.hex}"
  description  = "Service account to manage destination Kafka cluster"
}

# ------------------------------------------------------
# ROLE BINDINGS
# ------------------------------------------------------

resource "confluent_role_binding" "dest-app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.dest-app-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.destenv.resource_name  
}


# ------------------------------------------------------
# DESTINATION SCHEMA REGISTRY API KEYS
# ------------------------------------------------------

resource "confluent_api_key" "dest-schema-registry-api-key" {
  display_name = "env-manager-schema-registry-api-key"
  description  = "Schema Registry API Key that is owned by 'destination-app-manager' service account"
  owner {
    id          = confluent_service_account.dest-app-manager.id
    api_version = confluent_service_account.dest-app-manager.api_version
    kind        = confluent_service_account.dest-app-manager.kind
  }
  managed_resource {
    id          = data.confluent_schema_registry_cluster.destsr.id
    api_version = data.confluent_schema_registry_cluster.destsr.api_version
    kind        = data.confluent_schema_registry_cluster.destsr.kind
    environment {
      id = confluent_environment.destenv.id
    }
  }
}

# ------------------------------------------------------
# KAFKA API KEY
# ------------------------------------------------------

resource "confluent_api_key" "dest-app-manager-kafka-api-key" {
  display_name           = "destination-app-manager-kafka-api-key-${random_id.env_display_id.hex}"
  description            = "Kafka API Key that is owned by 'destination-app-manager' service account"
  disable_wait_for_ready = true
  owner {
    id          = confluent_service_account.dest-app-manager.id
    api_version = confluent_service_account.dest-app-manager.api_version
    kind        = confluent_service_account.dest-app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.destcluster.id
    api_version = confluent_kafka_cluster.destcluster.api_version
    kind        = confluent_kafka_cluster.destcluster.kind

    environment {
      id = confluent_environment.destenv.id
    }
  }
  depends_on = [
    confluent_role_binding.dest-app-manager-kafka-cluster-admin,
    confluent_private_link_attachment_connection.destplac
  ]
}