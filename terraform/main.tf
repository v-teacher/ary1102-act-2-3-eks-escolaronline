terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
  }
}
provider "aws" {
  region  = "us-east-1"
  profile = "learner-lab"
  default_tags { tags = { Project = "ary1102-act23", ManagedBy = "terraform" } }
}
locals {
  name = "ary1102-act23"
  azs  = ["us-east-1a", "us-east-1b"]
}
data "aws_iam_role" "cluster" { name = "c229405a5779285l16665412t1w270457-LabEksClusterRole-hLXDTGjh7lQ2" }
data "aws_iam_role" "nodes" { name = "c229405a5779285l16665412t1w270457647-LabEksNodeRole-4CuhhM9OLKan" }
resource "aws_vpc" "main" {
  cidr_block           = "10.23.0.0/22"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = local.name }
}
resource "aws_internet_gateway" "main" { vpc_id = aws_vpc.main.id }
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-public-${count.index}", "kubernetes.io/role/elb" = "1" }
}
resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index + 2)
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name}-app-${count.index}", "kubernetes.io/role/internal-elb" = "1" }
}
resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 3, count.index + 4)
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name}-data-${count.index}" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]
}
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}
resource "aws_route_table" "data" { vpc_id = aws_vpc.main.id }
resource "aws_route_table_association" "data" {
  count          = 2
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}
resource "aws_eks_cluster" "main" {
  name     = local.name
  version  = "1.34"
  role_arn = data.aws_iam_role.cluster.arn
  vpc_config {
    subnet_ids              = aws_subnet.app[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
  }
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
  compute_config {
    enabled    = true
    node_pools = []
  }
  kubernetes_network_config {
    elastic_load_balancing { enabled = true }
  }
  storage_config {
    block_storage { enabled = true }
  }
}
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = local.name
  node_role_arn   = data.aws_iam_role.nodes.arn
  subnet_ids      = aws_subnet.app[*].id
  instance_types  = ["t3.medium"]
  ami_type        = "AL2023_x86_64_STANDARD"
  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }
  depends_on = [aws_route_table_association.app]
}
resource "aws_security_group" "db" {
  name   = "${local.name}-db"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }
}
resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.data[*].id
}
resource "random_password" "db" {
  length  = 24
  special = false
}
resource "aws_db_instance" "main" {
  identifier              = local.name
  engine                  = "mysql"
  engine_version          = "8.0.43"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  multi_az                = true
  db_name                 = "escolar_online"
  username                = "alumno"
  password                = random_password.db.result
  storage_encrypted       = true
  publicly_accessible     = false
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  skip_final_snapshot     = true
  backup_retention_period = 1
}
resource "aws_ecr_repository" "app" {
  for_each     = toset(["frontend", "get-products", "create-product", "update-product", "delete-product"])
  name         = "${local.name}-${each.key}"
  force_delete = true
  image_scanning_configuration { scan_on_push = true }
}
output "db_host" { value = aws_db_instance.main.address }
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
output "cluster_name" { value = aws_eks_cluster.main.name }
