module "rke" {
  source              = "../../"
  network_name        = "dnv-mgmt"
  ssh_keypair_name    = "dnv" # Local path to public SSH key
  bastion_ssh_key_path     = ""    # Local path to SSH key
  host_ssh_key        = ""
  floating_ip_pool    = "public"         # Name of the floating IP pool (often same as the external network name)
  image_name          = "Dinivas Docker" # Name of an image to boot the nodes from (OS should be Ubuntu 16.04)
  master_flavor_name  = "dinivas.large"  # Master node flavor name
  master_count        = 1                # Number of masters to deploy (should be an odd number)
  service_flavor_name = "dinivas.large"  # Service node flavor name (service nodes are general purpose)
  service_count       = 2                # Number of service nodes to deploy
  edge_flavor_name    = "dinivas.large"  # Edge node flavor name (edge nodes run ingress controller and balance the API)
  edge_count          = 1                # Number of edge nodes to deploy (should be at least 1)
}
