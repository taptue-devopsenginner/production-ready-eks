variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {
  type    = string
  default = "production-ready-eks"
}
variable "kubernetes_version" {
  description = "Choose an EKS version currently supported in us-east-1 before planning."
  type        = string
}
variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.0.0/20", "10.40.16.0/20", "10.40.32.0/20"]
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.128.0/20", "10.40.144.0/20", "10.40.160.0/20"]
}
variable "single_nat_gateway" {
  description = "True reduces dev cost but introduces an AZ-level egress dependency."
  type        = bool
  default     = true
}
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.large"]
}
variable "node_desired_size" {
  type    = number
  default = 2
}
variable "node_min_size" {
  type    = number
  default = 2
}
variable "node_max_size" {
  type    = number
  default = 4
}
variable "endpoint_public_access" {
  type    = bool
  default = false
}
variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = []
}
