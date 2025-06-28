variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  default     = "rg-billing-archival"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "West US"
}

variable "cosmos_db_name" {
  type        = string
  description = "Cosmos DB database name"
  default     = "BillingDB"
}

variable "cosmos_container_name" {
  type        = string
  description = "Cosmos DB container name"
  default     = "BillingRecords"
}

variable "storage_container_name" {
  type        = string
  description = "Blob container name for archived data"
  default     = "archived-billing-records"
}
