output "cosmos_account_endpoint" {
  value = azurerm_cosmosdb_account.cosmos.endpoint
}

output "cosmos_account_primary_key" {
  value     = azurerm_cosmosdb_account.cosmos.primary_key
  sensitive = true
}

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "storage_container_name" {
  value = azurerm_storage_container.archive.name
}

output "function_app_name" {
  value = azurerm_linux_function_app.func.name
}
