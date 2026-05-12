variable "aws_region" {
  description = "Região AWS onde os recursos serão criados. Use sa-east-1 para Brasil ou us-east-1 para seguir o laboratório original."
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Nome base do projeto."
  type        = string
  default     = "photo-catalog"
}

variable "environment" {
  description = "Ambiente de deploy."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Responsável pelo projeto para tags."
  type        = string
  default     = "portfolio"
}

variable "log_retention_days" {
  description = "Retenção dos logs das Lambdas no CloudWatch."
  type        = number
  default     = 14
}

variable "admin_api_rate_limit" {
  description = "Limite médio de requisições por segundo no usage plan da API admin."
  type        = number
  default     = 10
}

variable "admin_api_burst_limit" {
  description = "Pico de requisições simultâneas no usage plan da API admin."
  type        = number
  default     = 20
}

variable "enable_waf" {
  description = "Cria AWS WAF com regra gerenciada e rate limit para as APIs."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Limite de requisições por IP em 5 minutos quando WAF estiver habilitado."
  type        = number
  default     = 1000
}
