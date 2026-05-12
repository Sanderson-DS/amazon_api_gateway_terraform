import json
import os
from decimal import Decimal
from typing import Any, Dict

import boto3
from boto3.dynamodb.conditions import Key

TABLE_NAME = os.environ["TABLE_NAME"]
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

HTML_DOC = """<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Coleção de Fotos API</title>
  <style>
    body { color:#1f2937; font-family: Arial, sans-serif; max-width: 860px; margin: 40px auto; padding: 0 20px; line-height: 1.6; }
    code, pre { background:#f3f4f6; border-radius:8px; padding:4px 8px; }
    pre { padding:16px; overflow:auto; }
    h1 { color:#111827; }
  </style>
</head>
<body>
  <h1>Coleção de Fotos API</h1>
  <p>API pública para consulta de metadados das imagens cadastradas no catálogo.</p>
  <h2>Endpoints</h2>
  <p>Consulta pelo ID:</p>
  <pre><code>GET /fotos/1</code></pre>
  <p>Consulta por assunto:</p>
  <pre><code>GET /fotos/assunto?nome=Capa_Artigo</code></pre>
  <p>Consulta por assunto e coleção:</p>
  <pre><code>GET /fotos/consulta?assunto=Capa_Artigo&colecao=DesignSystem</code></pre>
  <p>Consulta por assunto e descrição:</p>
  <pre><code>GET /fotos/pesquisa?assunto=Capa_Artigo&descricao=Design_UX</code></pre>
</body>
</html>"""


def decimal_default(value: Any) -> Any:
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError


def response(status_code: int, body: Any, content_type: str = "application/json") -> Dict[str, Any]:
    if content_type == "application/json":
        payload = json.dumps(body, default=decimal_default, ensure_ascii=False)
    else:
        payload = str(body)

    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": content_type,
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": payload,
    }


def ok(items: Any, count: int | None = None) -> Dict[str, Any]:
    if isinstance(items, list):
        return response(200, {"count": len(items) if count is None else count, "items": items})
    return response(200, items)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    http_method = event.get("httpMethod", "GET")
    if http_method == "OPTIONS":
        return response(204, {})

    path = event.get("path", "")
    query = event.get("queryStringParameters") or {}

    try:
        if path.rstrip("/") == "/fotos":
            return response(200, HTML_DOC, "text/html; charset=utf-8")

        if path.startswith("/fotos/assunto"):
            assunto = query.get("nome")
            if not assunto:
                return response(400, {"message": "Parâmetro obrigatório: nome"})
            result = table.query(
                IndexName="assunto-index",
                KeyConditionExpression=Key("assunto").eq(assunto),
            )
            return ok(result.get("Items", []), result.get("Count"))

        if path.startswith("/fotos/consulta") or path.startswith("/fotos/assuntoecolecao"):
            assunto = query.get("assunto")
            colecao = query.get("colecao")
            if not assunto or not colecao:
                return response(400, {"message": "Parâmetros obrigatórios: assunto e colecao"})
            result = table.query(
                IndexName="assunto-colecao-index",
                KeyConditionExpression=Key("assunto").eq(assunto) & Key("colecao").eq(colecao),
            )
            return ok(result.get("Items", []), result.get("Count"))

        if path.startswith("/fotos/pesquisa"):
            assunto = query.get("assunto")
            descricao = query.get("descricao")
            if not assunto or not descricao:
                return response(400, {"message": "Parâmetros obrigatórios: assunto e descricao"})
            result = table.query(
                IndexName="assunto-descricao-index",
                KeyConditionExpression=Key("assunto").eq(assunto) & Key("descricao").eq(descricao),
            )
            return ok(result.get("Items", []), result.get("Count"))

        if path.startswith("/fotos/"):
            raw_id = path.rsplit("/", 1)[-1]
            if not raw_id.isdigit():
                return response(400, {"message": "ID deve ser numérico"})
            result = table.get_item(Key={"id": int(raw_id)})
            item = result.get("Item")
            if not item:
                return response(404, {"message": "Foto nao encontrada"})
            return ok(item)

        return response(404, {"message": "Rota nao encontrada"})
    except Exception as exc:
        return response(500, {"message": "Erro interno", "detail": str(exc)})
