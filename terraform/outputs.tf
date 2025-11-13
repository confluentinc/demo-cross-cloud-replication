# =====================================================
# CONSOLIDATED RESOURCE IDS AND OUTPUTS
# =====================================================


resource "local_file" "replication_commands" {
  filename = "./replication_commands.txt"
  content  = <<-EOT
#STEP1: Update your hosts file to route through proxies

macOS/Linux:
echo '${aws_instance.nginx_proxy.public_ip} ${trimsuffix(replace(confluent_kafka_cluster.sourcecluster.rest_endpoint, "https://", ""), ":443")}' | sudo tee -a /etc/hosts
echo '${azurerm_public_ip.nginx_public_ip.ip_address} ${trimsuffix(replace(confluent_kafka_cluster.destcluster.rest_endpoint, "https://", ""), ":443")}' | sudo tee -a /etc/hosts

Windows (CMD):
echo ${aws_instance.nginx_proxy.public_ip} ${trimsuffix(replace(confluent_kafka_cluster.sourcecluster.rest_endpoint, "https://", ""), ":443")} >> C:\\Windows\\System32\\drivers\\etc\\hosts
echo ${azurerm_public_ip.nginx_public_ip.ip_address} ${trimsuffix(replace(confluent_kafka_cluster.destcluster.rest_endpoint, "https://", ""), ":443")} >> C:\\Windows\\System32\\drivers\\etc\\hosts

#STEP2: Login to Confluent CLI
confluent login

#STEP3: Set the destination (Azure) environment context
confluent environment use ${confluent_environment.destenv.id}

#STEP4: Create link-config.properties and create the cluster link (destination -> source)

macOS/Linux:
cat > link-config.properties <<'EOF'
auto.create.mirror.topics.enable=true
consumer.offset.sync.enable=true
auto.create.mirror.topics.filters={"topicFilters": [{"name": "*", "patternType": "LITERAL", "filterType": "INCLUDE"}]}
EOF
confluent kafka link create cross-cloud-link \
  --cluster ${confluent_kafka_cluster.destcluster.id} \
  --source-cluster ${confluent_kafka_cluster.sourcecluster.id} \
  --source-bootstrap-server ${confluent_kafka_cluster.sourcecluster.bootstrap_endpoint} \
  --source-api-key ${confluent_api_key.app-manager-kafka-api-key.id} \
  --source-api-secret ${confluent_api_key.app-manager-kafka-api-key.secret} \
  --config link-config.properties

Windows (CMD):
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

#[OPTIONAL] STEP4b: Create a mirror topic if auto.create.mirror.topics is disabled
confluent kafka mirror create sample_data_orders --link cross-cloud-link --cluster ${confluent_kafka_cluster.destcluster.id}

#STEP5: Set your local Confluent CLI context to the source environment
confluent environment use ${confluent_environment.sourceenv.id}

#STEP6: Create a schema exporter from source to destination (run locally)
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


output "update_hosts_macos_linux_all" {
  description = "Mac/Linux: Append both AWS and Azure entries to /etc/hosts in one command"
  value       = <<EOT
echo '${aws_instance.nginx_proxy.public_ip} ${trimsuffix(replace(confluent_kafka_cluster.sourcecluster.rest_endpoint, "https://", ""), ":443")}' | sudo tee -a /etc/hosts && echo '${azurerm_public_ip.nginx_public_ip.ip_address} ${trimsuffix(replace(confluent_kafka_cluster.destcluster.rest_endpoint, "https://", ""), ":443")}' | sudo tee -a /etc/hosts
EOT
}

output "update_hosts_windows_all" {
  description = "Windows: Append both AWS and Azure entries to hosts file in one command (run CMD as Administrator)"
  value       = <<EOT
echo ${aws_instance.nginx_proxy.public_ip} ${trimsuffix(replace(confluent_kafka_cluster.sourcecluster.rest_endpoint, "https://", ""), ":443")} >> C:\\Windows\\System32\\drivers\\etc\\hosts & echo ${azurerm_public_ip.nginx_public_ip.ip_address} ${trimsuffix(replace(confluent_kafka_cluster.destcluster.rest_endpoint, "https://", ""), ":443")} >> C:\\Windows\\System32\\drivers\\etc\\hosts
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
  EOT
  sensitive = true
}
