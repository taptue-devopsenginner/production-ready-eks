resource "aws_route" "private_nat" {
  count                  = var.single_nat_gateway ? 1 : local.az_count
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}
