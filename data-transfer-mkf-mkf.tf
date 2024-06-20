# Infrastructure for the Yandex Cloud Managed Service for Apache Kafka® and Data Transfer
#
# RU: https://yandex.cloud/ru/docs/data-transfer/tutorials/mkf-to-mkf
# EN: https://yandex.cloud/en/docs/data-transfer/tutorials/mkf-to-mkf

# Configure the parameters of the source and target clusters:

locals {
  # Source Managed Service for Apache Kafka® cluster settings:
  source_kf_version    = "" # Apache Kafka® version
  source_user_name     = "" # Username of the Apache Kafka® cluster
  source_user_password = "" # Apache Kafka® user's password

  # Target Managed Service for Apache Kafka® cluster settings:
  target_kf_version = "" # Apache Kafka® version

  # Specify these settings ONLY AFTER the YDB database is created. Then run "terraform apply" command again.
  # You should set up the target endpoint using the management console to obtain its ID
  source_endpoint_id = "" # Set the source endpoint id
  target_endpoint_id = "" # Set the target endpoint id
  transfer_enabled   = 0  # Value '0' disables the transfer creation before the source endpoint is created manually. After that, set to '1' to enable the transfer.

  # The following settings are predefined. Change them only if necessary.
  network_name        = "mkf_network"              # Name of the network
  subnet_name         = "mkf_subnet-a"             # Name of the subnet
  security_group_name = "mkf_security_group"       # Name of the security group
  source_cluster_name = "mkf-cluster-source"       # Name of the Apache Kafka® source cluster
  source_topic_name   = "sensors"                  # Name of the Apache Kafka® topic for the source cluster
  target_cluster_name = "mkf-cluster-target"       # Name of the Apache Kafka® target cluster
  target_topic_name   = "sensors"                  # Name of the Apache Kafka® topic for the target cluster
  transfer_name       = "transfer-from-mkf-to-mkf" # Name of the transfer between the Managed Service for Apache Kafka® clusters
}

# Network infrastructure

resource "yandex_vpc_network" "mkf_network" {
  description = "Network for the Managed Service for Apache Kafka® clusters"
  name        = local.network_name
}

resource "yandex_vpc_subnet" "mkf_subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone for the Managed Service for Apache Kafka® clusters network"
  name           = local.subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mkf_network.id
  v4_cidr_blocks = ["10.129.0.0/24"]
}

resource "yandex_vpc_security_group" "mkf_security_group" {
  description = "Security group for the Managed Service for Apache Kafka® clusters"
  network_id  = yandex_vpc_network.mkf_network.id
  name        = local.security_group_name

  ingress {
    description    = "Allow incoming traffic from the port 9091"
    protocol       = "TCP"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Infrastructure for the Managed Service for Apache Kafka® clusters

resource "yandex_mdb_kafka_cluster" "mkf-cluster-source" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = local.source_cluster_name
  network_id         = yandex_vpc_network.mkf_network.id
  security_group_ids = [yandex_vpc_security_group.mkf_security_group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = local.source_kf_version
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro" # 2 vCPU, 8 GB
      }
    }

    zones = [
      "ru-central1-a"
    ]
  }

  depends_on = [
    yandex_vpc_subnet.mkf_subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® source cluster
resource "yandex_mdb_kafka_topic" "sensors-source" {
  cluster_id         = yandex_mdb_kafka_cluster.mkf-cluster-source.id
  name               = local.source_topic_name
  partitions         = 3
  replication_factor = 1
}

# User of the Managed service for the Apache Kafka® source cluster
resource "yandex_mdb_kafka_user" "mkf-user-source" {
  cluster_id = yandex_mdb_kafka_cluster.mkf-cluster-source.id
  name       = local.source_user_name
  password   = local.source_user_password
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors-source.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors-source.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

resource "yandex_mdb_kafka_cluster" "mkf-cluster-target" {
  description        = "Managed Service for Apache Kafka® cluster"
  environment        = "PRODUCTION"
  name               = local.target_cluster_name
  network_id         = yandex_vpc_network.mkf_network.id
  security_group_ids = [yandex_vpc_security_group.mkf_security_group.id]

  config {
    brokers_count = 1
    version       = local.target_kf_version
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro" # 2 vCPU, 8 GB
      }
    }

    zones = [
      "ru-central1-a"
    ]
  }

  depends_on = [
    yandex_vpc_subnet.mkf_subnet-a
  ]
}

# Topic of the Managed Service for Apache Kafka® target cluster
resource "yandex_mdb_kafka_topic" "sensors-target" {
  cluster_id         = yandex_mdb_kafka_cluster.mkf-cluster-target.id
  name               = local.target_topic_name
  partitions         = 1
  replication_factor = 1
}

# User of the Managed service for the Apache Kafka ® target cluster
resource "yandex_mdb_kafka_user" "mkf-user-target" {
  cluster_id = yandex_mdb_kafka_cluster.mkf-cluster-target.id
  name       = local.source_user_name
  password   = local.source_user_password
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors-target.name
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = yandex_mdb_kafka_topic.sensors-target.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# Data Transfer infrastructure

resource "yandex_datatransfer_transfer" "mkf-mkf-transfer" {
  description = "Transfer between the Managed Service for Apache Kafka® clusters"
  count       = local.transfer_enabled
  name        = local.transfer_name
  source_id   = local.source_endpoint_id
  target_id   = local.target_endpoint_id
  type        = "INCREMENT_ONLY" # Replicate data from the source Apache Kafka® topic
}
