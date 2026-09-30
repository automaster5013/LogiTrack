output "load_balancer_dns_name" { value = aws_lb.edge.dns_name }
output "load_balancer_arn" { value = aws_lb.edge.arn }
output "load_balancer_zone_id" { value = aws_lb.edge.zone_id }
output "ecs_cluster_arn" { value = aws_ecs_cluster.production.arn }
output "api_service_name" { value = aws_ecs_service.api.name }
output "web_service_name" { value = aws_ecs_service.web.name }
output "web_target_group_arn" { value = aws_lb_target_group.web.arn }
