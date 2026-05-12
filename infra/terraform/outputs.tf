output "bucket_name" {
  description = "Bucket privado de upload das imagens."
  value       = aws_s3_bucket.uploads.bucket
}

output "dynamodb_table_name" {
  description = "Tabela DynamoDB de metadados."
  value       = aws_dynamodb_table.photos.name
}

output "public_api_url" {
  description = "URL base da API pública."
  value       = aws_api_gateway_stage.public.invoke_url
}

output "admin_api_url" {
  description = "URL base da API administrativa."
  value       = aws_api_gateway_stage.admin.invoke_url
}

output "admin_api_key_id" {
  description = "ID da API key administrativa. Use AWS CLI com --include-value para obter o valor."
  value       = aws_api_gateway_api_key.admin.id
}

output "example_public_docs_url" {
  description = "Documentação pública em HTML."
  value       = "${aws_api_gateway_stage.public.invoke_url}/fotos"
}
