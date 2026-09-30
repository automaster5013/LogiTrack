output "regional_alarm_topic_arn" {
  description = "Use as alarm_topic_arn for the production data and compute roots."
  value       = aws_sns_topic.regional.arn
}

output "global_alarm_topic_arn" {
  description = "Use as global_alarm_topic_arn for the production certificates and edge roots."
  value       = aws_sns_topic.global.arn
}

output "paging_subscription_arns" {
  description = "Confirmed subscription ARNs; apply does not complete while either HTTPS receiver is unconfirmed."
  value = {
    regional = aws_sns_topic_subscription.regional_paging.arn
    global   = aws_sns_topic_subscription.global_paging.arn
  }
}
