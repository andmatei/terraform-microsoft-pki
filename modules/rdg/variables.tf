variable "ad_id" {
  type        = string
  description = "AD ID"
}

variable "rdg_hosts_count" {
  type        = number
  default     = 1
  description = "Number of RDG hosts to create"
}

variable "vpc_id" {
  type        = string
  description = "ID of VPC"
}

variable "public_subnets" {
  type        = list(string)
  default     = []
  description = "List of IDs of the public subnets that"
}

variable "instance_type" {
  type        = string
  default     = "t3.2xlarge"
  description = "Amazon EC2 instance type for the Remote Desktop Gateway instances."
}

variable "key_pair" {
  type        = string
  description = "Public/private key pairs allow you to securely connect to your instance after it launches."
}

variable "ami_id" {
  type        = string
  description = "ID of the AMI to be installet on the RDG hosts."
}

variable "cidr_block" {
  type        = string
  description = "Allowed CIDR Block for external access to the Remote Desktop Gateways."
}

