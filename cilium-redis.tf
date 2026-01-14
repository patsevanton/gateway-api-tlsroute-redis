resource "yandex_kubernetes_cluster" "cilium-redis" {
  name       = "cilium-redis"
  network_id = yandex_vpc_network.k8s-network.id

  master {
    version = "1.33"
    zonal {
      zone      = yandex_vpc_subnet.k8s-subnet.zone
      subnet_id = yandex_vpc_subnet.k8s-subnet.id
    }
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.allow-all-sg.id]
  }

  service_account_id      = yandex_iam_service_account.sa-k8s-admin.id
  node_service_account_id = yandex_iam_service_account.sa-k8s-admin.id
  release_channel         = "RAPID"
  cluster_ipv4_range      = "10.114.0.0/16"
  service_ipv4_range      = "10.98.0.0/16"

  depends_on = [yandex_resourcemanager_folder_iam_member.sa-k8s-admin-permissions]
}

resource "yandex_kubernetes_node_group" "k8s_node_group_cilium_redis" {
  cluster_id = yandex_kubernetes_cluster.cilium-redis.id
  name       = "node-group-cilium-redis"
  version    = "1.33"

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat        = true
      subnet_ids = [yandex_vpc_subnet.k8s-subnet.id]
    }

    resources {
      cores  = 2
      memory = 8
    }

    boot_disk {
      type = "network-ssd"
      size = 65
    }

    metadata = {
      ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    }

  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-b"
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.cilium-redis.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.cilium-redis.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}

resource "helm_release" "envoy_gateway" {
  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.6.2"
  namespace        = "envoy-gateway"
  create_namespace = true
  depends_on       = [yandex_kubernetes_node_group.k8s_node_group_cilium_redis]

  set = [
    {
      name  = "service.type"
      value = "LoadBalancer"
    },
    {
      name  = "service.loadBalancerIP"
      value = yandex_vpc_address.addr.external_ipv4_address[0].address
    }
  ]
}

resource "local_file" "envoyproxy_yaml" {
  content = templatefile("${path.module}/envoyproxy.yaml.tpl", {
    load_balancer_ip = yandex_vpc_address.addr.external_ipv4_address[0].address
  })
  filename = "${path.module}/envoyproxy.yaml"
}

output "get_credentials_command_cilium_redis" {
  description = "Command to get kubeconfig for the Cilium Redis cluster"
  value       = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.cilium-redis.id} --external --force"
}