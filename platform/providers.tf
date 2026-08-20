terraform {
  backend "local" {}

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = "../secrets/${var.env_name}/kubeconfig.yaml"
  }
}