output "vpc_id" { value = aws_vpc.production.id }
output "private_subnet_ids" { value = aws_subnet.data[*].id }
output "application_security_group_id" { value = aws_security_group.application.id }
output "database_endpoint" { value = aws_db_instance.postgres.address }
output "database_port" { value = aws_db_instance.postgres.port }
output "cache_primary_endpoint" { value = aws_elasticache_replication_group.cache.primary_endpoint_address }
output "cache_port" { value = aws_elasticache_replication_group.cache.port }
output "kafka_bootstrap_brokers_sasl_scram" {
  value     = aws_msk_cluster.kafka.bootstrap_brokers_sasl_scram
  sensitive = true
}
output "kafka_scram_secret_arn" {
  value     = aws_secretsmanager_secret.kafka_scram.arn
  sensitive = true
}
output "master_user_secret_arn" {
  value     = aws_db_instance.postgres.master_user_secret[0].secret_arn
  sensitive = true
}
