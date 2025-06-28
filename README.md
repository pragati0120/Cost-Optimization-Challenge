# Cost-Optimization-Challenge

#  Azure Billing Records Cost Optimization Project

##  Overview

This project aims to **reduce costs** in a serverless Azure architecture by archiving older billing records stored in Cosmos DB to Azure Blob Storage.  

- Cosmos DB is used for storing billing data (each record ~300 KB).
- Data older than 90 days is rarely accessed but must remain available.
- We move these old records to Blob Storage and delete them from Cosmos DB, significantly reducing storage and RU costs.

---

##  Architecture

```
[API or App Service]
        │
        ▼
[Azure Cosmos DB]
        │
        ├── Active Records (< 90 days)
        │
        └── Old Records (≥ 90 days) ──► [Azure Function] ──► [Blob Storage Container]
                                                │
                                                └── Delete from Cosmos DB
```

---

## Deployment Steps

### 1. Infrastructure Setup (Terraform)

**Resources provisioned:**
- Resource Group
- Cosmos DB account & database
- Storage account & container
- App Service Plan & Function App

**Terraform folder structure:**

```
infra/
├── main.tf
├── variables.tf
├── outputs.tf
├── provider.tf
└── versions.tf
```

#### Example: `main.tf` snippet

```hcl
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "cosmosbilling${random_integer.rand.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "db" {
  name                = "BillingDB"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmos.name
}

resource "azurerm_cosmosdb_sql_container" "container" {
  name                  = "BillingRecords"
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.db.name
  partition_key_path    = "/customerId"
  throughput            = 400
}

resource "azurerm_storage_account" "sa" {
  name                     = "billingarch${random_integer.rand.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "archive" {
  name                  = "archived-billing-records"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}
```

---

### 2. Deploy Terraform

```bash
terraform init
terraform plan
terraform apply
```

---

### 3. Create Function App

```bash
az functionapp plan create --name billing-func-plan --resource-group rg-billing-archival --location eastus --number-of-workers 1 --sku EP1 --is-linux

az functionapp create   --name billing-archival-func   --storage-account <your-storage-account>   --resource-group rg-billing-archival   --plan billing-func-plan   --runtime python   --functions-version 4   --os-type Linux
```

---

### 4. Configure Function App settings

```bash
az functionapp config appsettings set --name billing-archival-func --resource-group rg-billing-archival --settings   COSMOS_ENDPOINT="https://<your-cosmos-account>.documents.azure.com:443/"   COSMOS_KEY="<your-cosmos-key>"   COSMOS_DATABASE="BillingDB"   COSMOS_CONTAINER="BillingRecords"   BLOB_CONN_STRING="<your-blob-connection-string>"   BLOB_CONTAINER="archived-billing-records"
```

---

##  Azure Function App Logic

###  `__init__.py`

```python
import logging
import os
import azure.functions as func
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient
import json
from datetime import datetime, timedelta

def main(mytimer: func.TimerRequest) -> None:
    utc_timestamp = datetime.utcnow().replace(tzinfo=None)

    endpoint = os.environ["COSMOS_ENDPOINT"]
    key = os.environ["COSMOS_KEY"]
    database_name = os.environ["COSMOS_DATABASE"]
    container_name = os.environ["COSMOS_CONTAINER"]

    blob_conn_str = os.environ["BLOB_CONN_STRING"]
    blob_container = os.environ["BLOB_CONTAINER"]

    cosmos_client = CosmosClient(endpoint, key)
    database = cosmos_client.get_database_client(database_name)
    container = database.get_container_client(container_name)

    blob_service_client = BlobServiceClient.from_connection_string(blob_conn_str)
    blob_container_client = blob_service_client.get_container_client(blob_container)

    cutoff_date = datetime.utcnow() - timedelta(days=90)
    cutoff_iso = cutoff_date.isoformat()

    query = f"SELECT * FROM c WHERE c.createdDate < '{cutoff_iso}'"
    items = list(container.query_items(query=query, enable_cross_partition_query=True))

    for item in items:
        doc_id = item['id']
        partition_key = item['customerId']

        blob_name = f"{doc_id}.json"
        blob_client = blob_container_client.get_blob_client(blob_name)

        blob_client.upload_blob(json.dumps(item), overwrite=True)
        logging.info(f"Archived document {doc_id} to blob {blob_name}")

        container.delete_item(doc_id, partition_key=partition_key)
        logging.info(f"Deleted document {doc_id} from Cosmos DB")

    logging.info(f"Function ran at {utc_timestamp}")
```

---

###  `function.json`

```json
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "name": "mytimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 * * * *"
    }
  ]
}
```

---

###  `requirements.txt`

```
azure-functions
azure-cosmos
azure-storage-blob
```

---

##  Deploy Function App code

```bash
zip -r func.zip *
az functionapp deployment source config-zip --resource-group rg-billing-archival --name billing-archival-func --src func.zip
```

---

##  Scheduling

- **Default:** Every hour (`0 0 * * * *`).
- **Change to daily:** Use `0 0 0 * * *` in `function.json`.

---

##  Monitoring

- Check logs in Azure Portal → Function App → Monitor blade.
- Verify blobs in your Storage container.

---

##  Conclusion

 With this setup, old billing records are archived seamlessly to blob storage, Cosmos DB cost is reduced, and you maintain read availability when needed.

---


