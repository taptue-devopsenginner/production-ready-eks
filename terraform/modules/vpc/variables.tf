variable "name" { type = string }
variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}
variable "availability_zones" {
  description = "Exactly three AZs are recommended for this EKS foundation."
  type        = list(string)
}
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "single_nat_gateway" {
  description = "One NAT gateway reduces dev cost; production should normally use one per AZ."
  type        = bool
  default     = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
