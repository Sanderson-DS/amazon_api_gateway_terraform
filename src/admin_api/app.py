import base64
import json
import os
import re
from typing import Any, Dict
from urllib.parse import unquote_plus

import boto3

BUCKET_NAME = os.environ["BUCKET_NAME"]
s3 = boto3.client("s3")

SAFE_KEY_PATTERN = re.compile(r"^\d+-[^/\\]+-[^/\\]+-[^/\\]+\.(jpg|jpeg)$", re.IGNORECASE)


def response(status_code: int, body: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST,DELETE,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,x-api-key",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }


def extract_item(event: Dict[str, Any]) -> str:
    params = event.get("pathParameters") or {}
    item = params.get("item") or event.get("path", "").rsplit("/", 1)[-1]
    item = unquote_plus(item)

    if not SAFE_KEY_PATTERN.match(item):
        raise ValueError("Nome inválido. Use: {id}-{assunto}-{colecao}-{descricao}.jpg")
    return item


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    method = event.get("httpMethod", "")

    if method == "OPTIONS":
        return response(204, {})

    try:
        item = extract_item(event)

        if method == "POST":
            content_type = (event.get("headers") or {}).get("Content-Type") or (event.get("headers") or {}).get("content-type") or "application/octet-stream"
            if content_type not in {"image/jpeg", "application/octet-stream"}:
                return response(415, {"message": "Content-Type permitido: image/jpeg"})

            body = event.get("body") or ""
            if event.get("isBase64Encoded"):
                payload = base64.b64decode(body)
            else:
                payload = body.encode("latin-1")

            if not payload:
                return response(400, {"message": "Body da imagem está vazio"})

            s3.put_object(
                Bucket=BUCKET_NAME,
                Key=item,
                Body=payload,
                ContentType="image/jpeg",
                ServerSideEncryption="AES256",
            )
            return response(200, {"message": "Envio com sucesso", "item": item})

        if method == "DELETE":
            s3.delete_object(Bucket=BUCKET_NAME, Key=item)
            return response(200, {"message": "Deletado com sucesso", "item": item})

        return response(405, {"message": "Método não permitido"})
    except ValueError as exc:
        return response(400, {"message": str(exc)})
    except Exception as exc:
        return response(500, {"message": "Erro interno", "detail": str(exc)})
