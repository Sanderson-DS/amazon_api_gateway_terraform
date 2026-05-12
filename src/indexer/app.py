import json
import logging
import os
import re
from datetime import datetime, timezone
from typing import Dict, Any
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

FILE_PATTERN = re.compile(
    r"^(?P<id>\d+)-(?P<assunto>[^-]+)-(?P<colecao>[^-]+)-(?P<descricao>[^.]+)\.(?P<ext>jpg|jpeg)$",
    re.IGNORECASE,
)


def parse_object_key(key: str) -> Dict[str, Any]:
    filename = key.rsplit("/", 1)[-1]
    match = FILE_PATTERN.match(filename)
    if not match:
        raise ValueError(
            "Nome de arquivo inválido. Use o padrão: "
            "{id}-{assunto}-{colecao}-{descricao}.jpg"
        )

    groups = match.groupdict()
    return {
        "id": int(groups["id"]),
        "assunto": groups["assunto"],
        "colecao": groups["colecao"],
        "descricao": groups["descricao"],
        "extensao": groups["ext"].lower(),
        "object_key": key,
    }


def handle_record(record: Dict[str, Any]) -> None:
    event_name = record.get("eventName", "")
    bucket_name = record["s3"]["bucket"]["name"]
    object_key = unquote_plus(record["s3"]["object"]["key"])

    logger.info(
        "Processando evento S3",
        extra={"event_name": event_name, "bucket": bucket_name, "object_key": object_key},
    )

    atributos = parse_object_key(object_key)

    if event_name.startswith("ObjectCreated:"):
        item = {
            **atributos,
            "bucket": bucket_name,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        table.put_item(Item=item)
        logger.info("Item indexado no DynamoDB: %s", json.dumps(item, ensure_ascii=False))
        return

    if event_name.startswith("ObjectRemoved:"):
        table.delete_item(Key={"id": atributos["id"]})
        logger.info("Item removido do DynamoDB: id=%s", atributos["id"])
        return

    logger.warning("Evento ignorado: %s", event_name)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    records = event.get("Records", [])

    failures = []
    for record in records:
        try:
            handle_record(record)
        except Exception as exc:
            logger.exception("Falha ao processar record")
            failures.append(str(exc))

    return {
        "statusCode": 200 if not failures else 500,
        "processed": len(records),
        "failures": failures,
    }
