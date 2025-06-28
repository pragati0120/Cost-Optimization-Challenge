terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.70.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.5.0"
    }
  }
}

provider "azurerm" {
  features {}
    subscription_id = "e2cb1307-7375-491d-b2e2-5a70a4b8abcf"
  
}

resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "sa" {
  name                     = "billingarch${random_integer.rand.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier            = "Standard"
  account_replication_type = "RAGRS"
  access_tier             = "Cool"
  lifecycle {
  ignore_changes = [tags]
}

}

resource "azurerm_storage_container" "archive" {
  name                 = "archive"
  storage_account_id   = azurerm_storage_account.sa.id
  container_access_type = "private"
}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmosbilling${random_integer.rand.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type         = "Standard"
  kind               = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
  lifecycle {
  ignore_changes = [tags]
}
  depends_on = [azurerm_resource_group.rg]

}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = var.cosmos_db_name
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "container" {
  name                = var.cosmos_container_name
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  database_name       = azurerm_cosmosdb_sql_database.db.name

  partition_key_paths   = ["/customerId"]
  partition_key_version = 2

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }
  }
}

resource "azurerm_service_plan" "plan" {
  name                = "billing-archival-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  sku_name            = "Y1"
}

resource "azurerm_linux_function_app" "func" {
  name                       = "billing-archival-func-${random_integer.rand.result}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  https_only                 = true

  site_config {}
  
  app_settings = {
    "AzureWebJobsStorage"         = azurerm_storage_account.sa.primary_connection_string
    "COSMOS_DB_CONNECTION_STRING" = azurerm_cosmosdb_account.cosmos.primary_sql_connection_string
  }
  depends_on = [azurerm_service_plan.plan]
}
