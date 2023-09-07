terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

## Data

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

## VPC

resource "aws_vpc" "vpc" {
  cidr_block           = local.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
}

## Public Subnets

resource "aws_subnet" "public_subnets" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = local.azs[count.index]
  cidr_block              = element(local.public_subnets, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = format("public-subnet-%s", element(local.azs, count.index))
    Tier = "Public"
  }
}

## Private Subnets

resource "aws_subnet" "sub_ca_subnets" {
  count = length(local.azs)

  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.azs[count.index]
  cidr_block        = element(local.sub_ca_subnets, count.index)

  tags = {
    Name = format("sub-ca-private-subnet-%s", element(local.azs, count.index))
    Tier = "Private"
  }
}

resource "aws_subnet" "hsm_subnets" {
  count = length(local.azs)

  vpc_id            = aws_vpc.vpc.id
  availability_zone = local.azs[count.index]
  cidr_block        = element(local.hsm_subnets, count.index)

  tags = {
    Name = format("hsm-private-subnet-%s", element(local.azs, count.index))
    Tier = "Private"
  }
}

## Internet Gateway

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
}

## Elastic IPs for Nat Gateways

resource "aws_eip" "eip_natgatways" {
  count = length(local.azs)

  vpc        = true
  depends_on = [aws_internet_gateway.internet_gateway]
}

## Nat Gateways

resource "aws_nat_gateway" "nat_gateways" {
  count = length(local.azs)

  allocation_id = aws_eip.eip_natgatways[count.index].id
  subnet_id     = aws_subnet.public_subnets[count.index].id
}

## Route Tables

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = local.internet
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_route_table" "private" {
  count = length(aws_nat_gateway.nat_gateways)

  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table_association" "private_sub_ca" {
  count = length(aws_subnet.sub_ca_subnets)

  subnet_id      = aws_subnet.sub_ca_subnets[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private_hsm" {
  count = length(aws_subnet.hsm_subnets)

  subnet_id      = aws_subnet.hsm_subnets[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route" "private_nat_gateway" {
  count = length(aws_nat_gateway.nat_gateways)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = local.internet
  nat_gateway_id         = aws_nat_gateway.nat_gateways[count.index].id
}

## CloudHSM

resource "aws_cloudhsm_v2_cluster" "cluster" {
  hsm_type   = "hsm1.medium"
  subnet_ids = aws_subnet.hsm_subnets[*].id
}

resource "aws_cloudhsm_v2_hsm" "hsm" {
  cluster_id = aws_cloudhsm_v2_cluster.cluster.cluster_id
  subnet_id  = aws_subnet.hsm_subnets[0].id
}

## MAD

locals {
  ad_subnet_ids = slice(aws_subnet.sub_ca_subnets[*].id, 0, min(length(aws_subnet.sub_ca_subnets), 2))
}

module "mad" {
  source = "./modules/ad"

  ds_managed_ad_directory_name = "corp.local"
  ds_managed_ad_short_name     = "corp"
  ds_managed_ad_edition        = "Enterprise"
  ds_managed_ad_subnet_ids     = local.ad_subnet_ids
  ds_managed_ad_vpc_id         = aws_vpc.vpc.id
}

## Root CA

data "aws_security_group" "security_group" {
  id = "sg-0054be4e3f3e7dc27"
}


module "ca" {
  source = "./modules/ca"

  key_name            = "Test"
  security_group_ids  = [data.aws_security_group.security_group.id]
  subnet_id           = aws_subnet.public_subnets[0].id
  ad_id               = module.mad.ds_managed_ad_id
  cloudhsm_cluster_id = aws_cloudhsm_v2_cluster.cluster.id
}

