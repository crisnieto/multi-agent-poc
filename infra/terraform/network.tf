locals {
  cluster_name = var.project_name
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "poc" {
  cidr_block           = "10.71.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "poc" {
  vpc_id = aws_vpc.poc.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.poc.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(aws_vpc.poc.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name                                          = "${var.project_name}-public-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.poc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.poc.id
  }
  tags = { Name = "${var.project_name}-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
