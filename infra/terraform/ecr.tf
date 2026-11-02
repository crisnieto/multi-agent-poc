resource "aws_ecr_repository" "app" {
  # ko --base-import-paths publica una imagen por comando. El instalador de
  # Substrate también construye envoy-dataplane con Docker.
  for_each = toset([
    "web", "control-plane", "codex-actor",
    "ate-idp-server", "ateapi", "atecontroller", "atelet", "atenet",
    "ateworker-gvisor", "kubernetes-secrets", "objectstore-plugin",
    "podcertcontroller", "envoy-dataplane",
  ])
  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = aws_ecr_repository.app
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the newest five PoC images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
