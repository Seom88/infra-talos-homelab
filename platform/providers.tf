terraform {
  backend "local" {}

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path = "../secrets/${var.env_name}/kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    config_path = "../secrets/${var.env_name}/kubeconfig.yaml"
  }
}