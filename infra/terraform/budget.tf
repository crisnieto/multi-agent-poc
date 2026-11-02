resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly-80usd"
  budget_type  = "COST"
  limit_amount = "80"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 70
    threshold_type             = "ABSOLUTE_VALUE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }
}
