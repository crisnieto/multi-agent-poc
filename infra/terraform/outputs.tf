output "cluster_name" { value = aws_eks_cluster.poc.name }
output "cluster_endpoint" { value = aws_eks_cluster.poc.endpoint }
output "snapshot_bucket" { value = aws_s3_bucket.snapshots.bucket }
output "aws_region" { value = var.aws_region }
output "node_group_name" { value = aws_eks_node_group.poc.node_group_name }
output "ecr_repositories" { value = { for name, repository in aws_ecr_repository.app : name => repository.repository_url } }
output "public_access_enabled" { value = var.public_access_enabled }
output "public_web_url" { value = var.public_access_enabled ? "http://${aws_lb.public_web[0].dns_name}" : "" }
