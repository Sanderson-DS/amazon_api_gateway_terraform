# Serverless Photo Catalog API — AWS + Terraform

Projeto de portfólio baseado no curso de API Gateway da Alura, refeito em uma versão mais profissional com Infraestrutura como Código.

A arquitetura cria uma API serverless para cadastrar, remover e consultar imagens armazenadas no S3, com indexação automática no DynamoDB por meio de Lambda.

## Arquitetura

```text
              ┌───────────────────────┐
              │   API pública          │
              │   GET /fotos           │
              │   GET /fotos/{id}      │
              │   GET /fotos/assunto   │
              │   GET /fotos/consulta  │
              │   GET /fotos/pesquisa  │
              └───────────┬───────────┘
                          │
                          ▼
                   Lambda public_api
                          │
                          ▼
                      DynamoDB

              ┌───────────────────────┐
              │   API admin            │
              │   POST /bucket/{item}  │──┐
              │   DELETE /bucket/{item}│  │ exige x-api-key
              └───────────┬───────────┘──┘
                          │
                          ▼
                    Lambda admin_api
                          │
                          ▼
                         S3
                          │ eventos ObjectCreated/ObjectRemoved
                          ▼
                    Lambda indexer
                          │
                          ▼
                      DynamoDB
```

## Melhorias em relação ao projeto original

- Infraestrutura em Terraform, sem cliques manuais no console.
- Separação entre API pública e API administrativa.
- API administrativa protegida por API Key e usage plan.
- DynamoDB com índices secundários para evitar `Scan` nas consultas principais.
- Lambda de indexação com validação de nome de arquivo e variáveis de ambiente.
- Logs no CloudWatch com retenção configurável.
- S3 privado, com bloqueio de acesso público, criptografia e lifecycle básico.
- WAF opcional para proteção da API pública e admin.
- Domínio customizado recomendado como evolução futura.
- Nenhum segredo versionado no GitHub.

## Estrutura do repositório

```text
.
├── infra/terraform        # Infraestrutura AWS
├── src/admin_api          # Lambda de upload/delete no S3
├── src/indexer            # Lambda acionada por eventos S3
├── src/public_api         # Lambda pública de consulta no DynamoDB
├── docs                   # Arquitetura, cleanup e checklist
├── samples/images         # Imagens de teste
└── scripts                # Scripts auxiliares
```

## Pré-requisitos

- Conta AWS.
- AWS CLI configurado.
- Terraform >= 1.6.
- Python 3.12 para desenvolvimento local.

## Deploy

```bash
cd infra/terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Após o deploy, veja os endpoints:

```bash
terraform output
```

Para recuperar a chave da API administrativa:

```bash
aws apigateway get-api-key \
  --api-key "$(terraform output -raw admin_api_key_id)" \
  --include-value \
  --query value \
  --output text
```

Não salve essa chave no GitHub.

## Teste rápido

```bash
export PUBLIC_URL="$(terraform output -raw public_api_url)"
export ADMIN_URL="$(terraform output -raw admin_api_url)"
export API_KEY="cole-a-chave-aqui"

curl "$PUBLIC_URL/fotos"

curl -X POST "$ADMIN_URL/bucket/1-Capa_Artigo-BI-DataScience.jpg" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: image/jpeg" \
  --data-binary "@../../samples/images/1-Capa_Artigo-BI-DataScience.jpg"

curl "$PUBLIC_URL/fotos/1"
```

## Destruir tudo

```bash
cd infra/terraform
terraform destroy
```

Se você criou recursos manualmente antes, use o checklist em `docs/aws-cleanup-checklist.md`.

## Segurança no GitHub

Antes de subir o repositório:

```bash
git status
git diff --staged
```

Não versionar:

- `terraform.tfstate`
- `terraform.tfvars`
- `.terraform/`
- chaves da AWS
- API keys
- secrets
- arquivos `.env`

