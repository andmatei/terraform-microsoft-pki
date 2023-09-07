variable "ad_id" {
  type        = string
  description = "AD ID"
}

variable "cloudhsm_cluster_id" {
  type        = string
  description = "CloudHSM cluster ID"
}

variable "key_name" {
  type        = string
  description = "Key name of the Key Pair"
  default     = null
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security groups"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID"
  default     = null
}

variable "root_ca" {
  type        = bool
  description = "Provision CA as Root CA"
  default     = true
}
