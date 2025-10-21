# =====================================================
# CONSOLIDATED RESOURCE IDS AND OUTPUTS
# =====================================================


resource "local_file" "replication_commands" {
  filename = "./replication_commands.txt"
  content  = <<-EOT
#STEP1: On the destination (azure) bastion host run this to login to Confluent CLI
confluent login

#STEP2: On the destination (azure) bastion host run this to use set the context of the CLI
confluent environment use  ${confluent_environment.destenv.id}

#STEP3: On the destination (azure) bastion host run this to create a config file for the cluster linking 

echo auto.create.mirror.topics.enable=true > link-config.properties
echo consumer.offset.sync.enable=true >> link-config.properties
echo auto.create.mirror.topics.filters={"topicFilters": [{"name": "*", "patternType": "LITERAL", "filterType": "INCLUDE"}]} >> link-config.properties

confluent kafka link create cross-cloud-link ^
  --cluster ${confluent_kafka_cluster.destcluster.id} ^
  --source-cluster ${confluent_kafka_cluster.sourcecluster.id} ^
  --source-bootstrap-server ${confluent_kafka_cluster.sourcecluster.bootstrap_endpoint} ^
  --source-api-key ${confluent_api_key.app-manager-kafka-api-key.id} ^
  --source-api-secret ${confluent_api_key.app-manager-kafka-api-key.secret} ^
  --config link-config.properties

#[OPTIONAL] STEP4: This is optional if you did not enable auto.create.mirror.topics. On the destination (azure) bastion host run this to create a cluster link
confluent kafka mirror create sample_data_orders --link cross-cloud-link --cluster ${confluent_kafka_cluster.destcluster.id}

#STEP5: On your local machine run this to create set your local Confluent CLI context to the source environment
confluent environment use  ${confluent_environment.sourceenv.id}

#STEP6: On your local machine run this to create a schema exporter from source to destination
confluent schema-registry exporter create cross-cloud-exporter --subjects ":*:" --config ./config.txt
  EOT 
  }

resource "local_file" "config" {
  filename = "./config.txt"
  content  = <<-EOT
schema.registry.url=${data.confluent_schema_registry_cluster.destsr.rest_endpoint}
basic.auth.credentials.source=USER_INFO
basic.auth.user.info=${confluent_api_key.dest-schema-registry-api-key.id}:${confluent_api_key.dest-schema-registry-api-key.secret}
  EOT 
  }


output "resource-ids" {
  description = "All resource IDs and connection details organized by service"
  value = <<-EOT

# =====================================================
# SOURCE CONFLUENT CLOUD (AWS)
# =====================================================
Source Environment ID: ${confluent_environment.sourceenv.id}
Source Kafka Cluster ID: ${confluent_kafka_cluster.sourcecluster.id}
Source Bootstrap Endpoint: ${confluent_kafka_cluster.sourcecluster.bootstrap_endpoint}
Source Schema Registry Endpoint: ${data.confluent_schema_registry_cluster.sourcesr.rest_endpoint}

Source Kafka API Key: ${confluent_api_key.app-manager-kafka-api-key.id}
Source Kafka API Secret: ${confluent_api_key.app-manager-kafka-api-key.secret}
Source Schema Registry API Key: ${confluent_api_key.schema-registry-api-key.id}
Source Schema Registry API Secret: ${confluent_api_key.schema-registry-api-key.secret}

# =====================================================
# DESTINATION CONFLUENT CLOUD (AZURE)
# =====================================================
Destination Environment ID: ${confluent_environment.destenv.id}
Destination Kafka Cluster ID: ${confluent_kafka_cluster.destcluster.id}
Destination Bootstrap Endpoint: ${confluent_kafka_cluster.destcluster.bootstrap_endpoint}
Destination Schema Registry Endpoint: ${data.confluent_schema_registry_cluster.destsr.rest_endpoint}

Destination Kafka API Key: ${confluent_api_key.dest-app-manager-kafka-api-key.id}
Destination Kafka API Secret: ${confluent_api_key.dest-app-manager-kafka-api-key.secret}
Destination Schema Registry API Key: ${confluent_api_key.dest-schema-registry-api-key.id}
Destination Schema Registry API Secret: ${confluent_api_key.dest-schema-registry-api-key.secret}

# =====================================================
# AWS WINDOWS BASTION HOST
# =====================================================
AWS Windows Jump Server IP: ${aws_instance.windows_instance.public_ip}
AWS Windows Jump Server Username: Administrator
AWS Windows Jump Server Password: ${nonsensitive(rsadecrypt(aws_instance.windows_instance.password_data, local_file.tf_key.content))}

# =====================================================
# AZURE WINDOWS BASTION HOST
# =====================================================
Azure Windows VM Public IP: ${azurerm_public_ip.vm_public_ip.ip_address}
Azure Windows VM Username: adminuser
Azure Windows VM Password: YourSecurePassword123!

  EOT
  sensitive = true
}