terraform {
  required_version = ">= 1.11"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
