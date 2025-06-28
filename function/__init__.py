import logging
import os
import azure.functions as func
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient
import json
from datetime import datetime, timedelta

def main(mytimer: func.TimerRequest) -> None:
    utc_timestamp = datetime.utcnow().replace(tzinfo=None)

    # Cosmos DB settings
    endpoint = os.environ["COSMOS_ENDPOINT"]
    key = os.environ["COSMOS_KEY"]
    database_name = os.environ["COSMOS_DATABASE"]
    container_name = os.environ["COSMOS_CONTAINER"]

    # Blob storage settings
    blob_conn_str = os.environ["BLOB_CONN_STRING"]
    blob_container = os.environ["BLOB_CONTAINER"]

    # Initialize clients
    cosmos_client = CosmosClient(endpoint, key)
    database = cosmos_client.get_database_client(database_name)
    container = database.get_container_client(container_name)

    blob_service_client = BlobServiceClient.from_connection_string(blob_conn_str)
    blob_container_client = blob_service_client.get_container_client(blob_container)

    # Archive records older than 90 days
    cutoff_date = datetime.utcnow() - timedelta(days=90)
    cutoff_iso = cutoff_date.isoformat()

    query = f"SELECT * FROM c WHERE c.createdDate < '{cutoff_iso}'"
    items = list(container.query_items(query=query, enable_cross_partition_query=True))

    for item in items:
        doc_id = item['id']
        partition_key = item['customerId']

        blob_name = f"{doc_id}.json"
        blob_client = blob_container_client.get_blob_client(blob_name)

        # Upload to blob
        blob_client.upload_blob(json.dumps(item), overwrite=True)
        logging.info(f"Archived document {doc_id} to blob {blob_name}")

        # Delete from Cosmos DB
        container.delete_item(doc_id, partition_key=partition_key)
        logging.info(f"Deleted document {doc_id} from Cosmos DB")

    logging.info(f"Function ran at {utc_timestamp}")
