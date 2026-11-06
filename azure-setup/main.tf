terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.13.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}

variable "region" {
  description = "The region in which resources will be created"
  type        = string
  default     = "westus3"
}

resource "azurerm_resource_group" "example" {
  name     = "rg-backstage-demo"
  location = var.region
}

resource "azurerm_kubernetes_automatic_cluster" "example" {
  name                = "aks-backstage-demo"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  identity {
    type = "SystemAssigned"
  }

  web_app_routing_ingress {
    istio_enabled = true
  }
}

resource "azapi_update_resource" "add_cluster_features" {
  type        = "Microsoft.ContainerService/managedClusters@2026-09-02-preview"
  resource_id = azurerm_kubernetes_automatic_cluster.example.id
  body = {
    properties = {
      ingressProfile = {
        gatewayAPI = {
          installation = "Standard"
        }
        webAppRouting = {
          defaultDomain = {
            enabled = true
          }
        }
      }
    }
  }

  response_export_values = ["*"]
}

resource "azurerm_role_assignment" "control_cluster_access" {
  scope                = azurerm_kubernetes_automatic_cluster.example.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "User"
}

output "rg_name" {
  value = azurerm_resource_group.example.name
}

output "aks_name" {
  value = azurerm_kubernetes_automatic_cluster.example.name
}

output "default_domain" {
  value = azapi_update_resource.add_cluster_features.output.properties.ingressProfile.webAppRouting.defaultDomain.domainName
}