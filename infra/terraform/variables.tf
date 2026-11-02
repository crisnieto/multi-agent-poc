variable "aws_region" {
  type        = string
  description = "Región de la ventana. Debe coincidir con el archivo de tarifas aprobado."
  default     = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "substrate-poc"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name debe ser un identificador DNS corto."
  }
}

variable "kubernetes_version" {
  type    = string
  default = "1.37"
  validation {
    condition     = var.kubernetes_version == "1.37"
    error_message = "La PoC está fijada a EKS 1.37 hasta validar otra versión."
  }
}

variable "node_instance_type" {
  type    = string
  default = "t3a.xlarge"
  validation {
    condition     = var.node_instance_type == "t3a.xlarge"
    error_message = "Cambiar el tipo de nodo exige actualizar tarifa y validación de capacidad; esta ventana usa t3a.xlarge."
  }
}

variable "node_count" {
  type    = number
  default = 1
  validation {
    condition     = var.node_count == 1
    error_message = "La PoC permite un solo nodo para limitar gasto."
  }
}

variable "worker_replicas" {
  type    = number
  default = 2
  validation {
    condition     = var.worker_replicas == 2
    error_message = "La prueba de multiplexación requiere dos workers."
  }
}

variable "allowed_api_cidrs" {
  type        = list(string)
  description = "IPs públicas del operador autorizadas al endpoint EKS."
  validation {
    condition     = length(var.allowed_api_cidrs) > 0 && alltrue([for cidr in var.allowed_api_cidrs : can(cidrhost(cidr, 0)) && cidr != "0.0.0.0/0" && cidr != "::/0" && cidr != "203.0.113.1/32"])
    error_message = "Indicar un CIDR real y restringido; se prohíbe el valor de ejemplo y 0.0.0.0/0."
  }
}

variable "budget_alert_emails" {
  type        = list(string)
  description = "Correos para alertas AWS Budgets de USD 40 y 70."
  validation {
    condition     = length(var.budget_alert_emails) > 0 && alltrue([for email in var.budget_alert_emails : can(regex("^[^@]+@[^@]+\\.[^@]+$", email)) && !endswith(email, "@example.com")])
    error_message = "Se requiere un destinatario de alertas real; se prohíbe example.com."
  }
}

variable "window_hours" {
  type    = number
  default = 2
  validation {
    condition     = var.window_hours > 0 && var.window_hours <= 2
    error_message = "Esta PoC limita la ventana AWS a 2 horas."
  }
}
