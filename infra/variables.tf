variable "app_name" {
  description = "Application name"
  type        = string
  default     = "pharmacy-stock"
}

variable "app_env" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "INFO"
}

variable "port" {
  description = "Application listening port"
  type        = number
  default     = 8080

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be between 1024 and 65535."
  }
}

variable "fail_mode" {
  description = "Readiness failure mode: 0 healthy, 1 unavailable"
  type        = number
  default     = 0

  validation {
    condition     = var.fail_mode == 0 || var.fail_mode == 1
    error_message = "fail_mode must be 0 or 1."
  }
}
