# Provision RKE
resource rke_cluster "cluster" {

  ###############################################
  # Kubernetes nodes
  ###############################################

  dynamic nodes {
    for_each = var.node_mappings
    content {
      address = nodes.value.address
      user    = nodes.value.user
      role    = ["controlplane", "worker", "etcd"]
      ssh_key = file("~/.ssh/id_rsa")
    }
  }


  bastion_host {
    address      = "${var.ssh_bastion_host}"
    user         = "${var.ssh_user}"
    ssh_key_path = "${var.bastion_ssh_key_path}"
    port         = 22
  }

  ingress {
    provider = "nginx"

    node_selector = {
      node_type = "edge"
    }
  }

  authentication {
    strategy = "x509"
  }

  ignore_docker_version = "${var.ignore_docker_version}"

  system_images {
    kubernetes                  = "rancher/hyperkube:v1.10.3-rancher2"
    etcd                        = "rancher/coreos-etcd:v3.1.12"
    alpine                      = "rancher/rke-tools:v0.1.9"
    nginx_proxy                 = "rancher/rke-tools:v0.1.9"
    cert_downloader             = "rancher/rke-tools:v0.1.9"
    kubernetes_services_sidecar = "rancher/rke-tools:v0.1.9"
    kube_dns                    = "rancher/k8s-dns-kube-dns-amd64:1.14.8"
    dnsmasq                     = "rancher/k8s-dns-dnsmasq-nanny-amd64:1.14.8"
    kube_dns_sidecar            = "rancher/k8s-dns-sidecar-amd64:1.14.8"
    kube_dns_autoscaler         = "rancher/cluster-proportional-autoscaler-amd64:1.0.0"
    pod_infra_container         = "rancher/pause-amd64:3.1"
  }

  # Workaround: make sure resources are created and deleted in the right order
  provisioner "local-exec" {
    command = "# ${join(",", var.rke_cluster_deps)}"
  }
}

# Write YAML configs
locals {
  api_access       = "https://${element(var.kubeapi_sans_list, 0)}:6443"
  api_access_regex = "/https://\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}:6443/"
}

resource local_file "kube_config_cluster" {
  count    = "${var.write_kube_config_cluster ? 1 : 0}"
  filename = "${path.root}/kube_config_cluster.yml"

  # Workaround: https://github.com/rancher/rke/issues/705
  content = "${replace(rke_cluster.cluster.kube_config_yaml, local.api_access_regex, local.api_access)}"
}

resource "local_file" "custer_yml" {
  count    = "${var.write_cluster_yaml ? 1 : 0}"
  filename = "${path.root}/cluster.yml"
  content  = "${rke_cluster.cluster.rke_cluster_yaml}"
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = "${local.api_access}"
  username               = "${rke_cluster.cluster.kube_admin_user}"
  client_certificate     = "${rke_cluster.cluster.client_cert}"
  client_key             = "${rke_cluster.cluster.client_key}"
  cluster_ca_certificate = "${rke_cluster.cluster.ca_crt}"
}

# Configure Helm provider
# Workaround: https://github.com/terraform-providers/terraform-provider-helm/issues/148
provider "helm" {
  service_account = "tiller"
  namespace       = "kube-system"
  install_tiller  = false

  kubernetes {
    host                   = "${local.api_access}"
    client_certificate     = "${rke_cluster.cluster.client_cert}"
    client_key             = "${rke_cluster.cluster.client_key}"
    cluster_ca_certificate = "${rke_cluster.cluster.ca_crt}"
  }
}

resource "kubernetes_service_account" "tiller" {
  metadata {
    name      = "tiller"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding" "tiller" {
  depends_on = ["kubernetes_service_account.tiller"]

  metadata {
    name = "tiller"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind = "User"
    name = "system:serviceaccount:kube-system:tiller"
  }
}

resource null_resource "tiller" {
  depends_on = ["kubernetes_cluster_role_binding.tiller"]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "${path.root}/kube_config_cluster.yml"
    }

    command = "helm init --service-account tiller --wait"
  }
}
