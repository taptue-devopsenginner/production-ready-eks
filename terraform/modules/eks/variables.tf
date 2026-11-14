variable "cluster_name" { type = string }
variable "kubernetes_version" {
  description = "EKS Kubernetes version supported in the target region."
  type        = string
}
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}
variable "node_desired_size" { type = number
  default = 2
}
variable "node_min_size" { type = number
  default = 2
}
variable "node_max_size" { type = number
  default = 4
}
variable "endpoint_public_access" {
  description = "Keep false for private-only API access; enable only with deliberate CIDR restrictions."
  type        = bool
  default     = false
}
variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
