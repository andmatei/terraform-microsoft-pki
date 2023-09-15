locals {
  internet = "0.0.0.0/0"

  vpc_cidr_block = "10.0.0.0/16"

  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]

  subnets        = [for cidr_block in cidrsubnets(local.vpc_cidr_block, 4, 4, 4) : cidrsubnets(cidr_block, 4, 4, 4)]
  public_subnets = local.subnets[0]
  sub_ca_subnets = local.subnets[1]
  hsm_subnets    = local.subnets[2]
}
