terraform {
  backend "s3" {
    bucket = "ops-account-dasan"
    key    = "terraform/backend"
    region = "us-east-2"
  }
}
locals {
  env_name         = "staging"
  aws_region       = "us-east-2"
  k8s_cluster_name = "ms-cluster"
}
variable "mysql_password" {
  type        = string
  description = "Expected to be retrieved from environment variable TF_VAR_mysql_password"
}

provider "aws" {
  region = local.aws_region
}

data "aws_eks_cluster" "msur" {
  name = module.aws-eks.eks_cluster_id
}


# Network configuration
module "aws-network" {
  source = "github.com/aravindvn/module-aws-network"

  env_name              = local.env_name
  vpc_name              = "msur-VPC"
  cluster_name          = local.k8s_cluster_name
  aws_region            = local.aws_region
  main_vpc_cidr         = "10.10.0.0/16"
  public_subnet_a_cidr  = "10.10.0.0/18"
  public_subnet_b_cidr  = "10.10.64.0/18"
  private_subnet_a_cidr = "10.10.128.0/18"
  private_subnet_b_cidr = "10.10.192.0/18"
}

# EKS configuration 
module "aws-eks" {
  source = "github.com/aravindvn/module-aws-kubernetes"

  ms_namespace       = "microservices"
  env_name           = local.env_name
  aws_region         = local.aws_region
  cluster_name       = local.k8s_cluster_name
  vpc_id             = module.aws-network.vpc_id
  cluster_subnet_ids = module.aws-network.subnet_ids

  nodegroup_subnet_ids     = module.aws-network.private_subnet_ids
  nodegroup_disk_size      = "20"
  nodegroup_instance_types = ["t3.medium"]
  nodegroup_desired_size   = 1
  nodegroup_min_size       = 1
  nodegroup_max_size       = 3
}

# GitOps Configuration
module "argo-cd-server" {
  source = "github.com/aravindvn/module-argo-cd"

  kubernetes_cluster_id        = module.aws-eks.eks_cluster_id
  kubernetes_cluster_name      = module.aws-eks.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-eks.eks_cluster_certificate_data
  kubernetes_cluster_endpoint  = module.aws-eks.eks_cluster_endpoint
  eks_nodegroup_id             = module.aws-eks.eks_cluster_nodegroup_id
}

module "aws-databases" {
  source = "github.com/aravindvn/module-aws-db"

  aws_region     = local.aws_region
  mysql_password = var.mysql_password
  vpc_id         = module.aws-network.vpc_id
  eks_id         = data.aws_eks_cluster.msur.id
  eks_sg_id      = module.aws-eks.eks_cluster_security_group_id
  subnet_a_id    = module.aws-network.private_subnet_ids[0]
  subnet_b_id    = module.aws-network.private_subnet_ids[1]
  env_name       = local.env_name
  route53_id     = module.aws-network.route53_id
}

module "traefik" {
  source = "github.com/aravindvn/module-aws-traefik/"

  aws_region                   = local.aws_region
  kubernetes_cluster_id        = data.aws_eks_cluster.msur.id
  kubernetes_cluster_name      = module.aws-eks.eks_cluster_name
  kubernetes_cluster_cert_data = module.aws-eks.eks_cluster_certificate_data
  kubernetes_cluster_endpoint  = module.aws-eks.eks_cluster_endpoint

  eks_nodegroup_id = module.aws-eks.eks_cluster_nodegroup_id
}
