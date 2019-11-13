# Create security group
module "secgroup" {
  source              = "./modules/secgroup"
  name_prefix         = "${var.cluster_prefix}"
  allowed_ingress_tcp = "${var.allowed_ingress_tcp}"
  allowed_ingress_udp = "${var.allowed_ingress_udp}"
}

# Create master node
module "master" {
  source             = "./modules/node"
  instance_count     = "${var.master_count}"
  name_prefix        = "${var.cluster_prefix}-master"
  flavor_name        = "${var.master_flavor_name}"
  image_name         = "${var.image_name}"
  network_name       = "${var.network_name}"
  secgroup_name      = "${module.secgroup.secgroup_name}"
  floating_ip_pool   = "${var.floating_ip_pool}"
  ssh_user           = "${var.ssh_user}"
  bastion_ssh_key_path    = "${var.bastion_ssh_key_path}"
  host_ssh_key       = "${var.host_ssh_key}"
  os_ssh_keypair     = "${var.ssh_keypair_name}"
  ssh_bastion_host   = "${element(module.edge.public_ip_list, 0)}"
  docker_version     = "${var.docker_version}"
  assign_floating_ip = "${var.master_assign_floating_ip}"
  role               = ["controlplane", "etcd"]

  labels = {
    node_type = "master"
  }
}

# Create service nodes
module "service" {
  source             = "./modules/node"
  instance_count     = "${var.service_count}"
  name_prefix        = "${var.cluster_prefix}-service"
  flavor_name        = "${var.service_flavor_name}"
  image_name         = "${var.image_name}"
  network_name       = "${var.network_name}"
  secgroup_name      = "${module.secgroup.secgroup_name}"
  floating_ip_pool   = "${var.floating_ip_pool}"
  ssh_user           = "${var.ssh_user}"
  bastion_ssh_key_path    = "${var.bastion_ssh_key_path}"
  host_ssh_key       = "${var.host_ssh_key}"
  os_ssh_keypair     = "${var.ssh_keypair_name}"
  ssh_bastion_host   = "${element(module.edge.public_ip_list, 0)}"
  docker_version     = "${var.docker_version}"
  assign_floating_ip = "${var.service_assign_floating_ip}"
  role               = ["worker"]

  labels = {
    node_type = "service"
  }
}

# Create edge nodes
module "edge" {
  source             = "./modules/node"
  instance_count     = "${var.edge_count}"
  name_prefix        = "${var.cluster_prefix}-edge"
  flavor_name        = "${var.edge_flavor_name}"
  image_name         = "${var.image_name}"
  network_name       = "${var.network_name}"
  secgroup_name      = "${module.secgroup.secgroup_name}"
  floating_ip_pool   = "${var.floating_ip_pool}"
  ssh_user           = "${var.ssh_user}"
  bastion_ssh_key_path    = "${var.bastion_ssh_key_path}"
  host_ssh_key       = "${var.host_ssh_key}"
  os_ssh_keypair     = "${var.ssh_keypair_name}"
  ssh_bastion_host   = "${element(module.edge.public_ip_list, 0)}"
  docker_version     = "${var.docker_version}"
  assign_floating_ip = "${var.edge_assign_floating_ip}"
  role               = ["worker"]

  labels = {
    node_type = "edge"
  }
}

# Compute dynamic dependencies for RKE provisioning step
locals {
  rke_cluster_deps = [
    "${join(",", module.master.prepare_nodes_id_list)}",  # Master stuff ...
    "${join(",", module.service.prepare_nodes_id_list)}", # Service stuff ...
    "${join(",", module.edge.prepare_nodes_id_list)}",    # Edge stuff ...
    "${join(",", module.edge.associate_floating_ip_id_list)}",
    "${join(",", module.secgroup.rule_id_list)}" # Other stuff ...
  ]
}

# Provision Kubernetes
module "rke" {
  source                    = "./modules/rke"
  rke_cluster_deps          = "${local.rke_cluster_deps}"
  node_mappings             = "${concat(module.master.node_rke_infos, module.service.node_rke_infos, module.edge.node_rke_infos)}"
  ssh_bastion_host          = "${element(module.edge.public_ip_list, 0)}"
  ssh_user                  = "${var.ssh_user}"
  bastion_ssh_key_path      = "${var.bastion_ssh_key_path}"
  kubeapi_sans_list         = "${module.edge.public_ip_list}"
  ignore_docker_version     = "${var.ignore_docker_version}"
  write_kube_config_cluster = "${var.write_kube_config_cluster}"
  write_cluster_yaml        = "${var.write_cluster_yaml}"
}
