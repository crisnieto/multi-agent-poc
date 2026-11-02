resource "aws_s3_bucket" "snapshots" {
  bucket        = "${var.project_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}-snapshots"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "snapshots" {
  bucket                  = aws_s3_bucket.snapshots.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id
  rule {
    id     = "abort-incomplete"
    status = "Enabled"
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "objectstore" {
  for_each           = toset(["atelet", "ate-api-server"])
  name               = "${var.project_name}-${each.key}-s3"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

data "aws_iam_policy_document" "objectstore" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.snapshots.arn]
  }
  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.snapshots.arn}/atespaces/*",
      "${aws_s3_bucket.snapshots.arn}/assets/*"
    ]
  }
}

resource "aws_iam_role_policy" "objectstore" {
  for_each = aws_iam_role.objectstore
  name     = "${var.project_name}-objectstore"
  role     = each.value.id
  policy   = data.aws_iam_policy_document.objectstore.json
}

# atelet pulls actor OCI bundles directly, outside the kubelet image pull path.
# Its Pod Identity role therefore needs its own ECR read permissions.
data "aws_iam_policy_document" "atelet_ecr" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.app["codex-actor"].arn]
  }
}

resource "aws_iam_role_policy" "atelet_ecr" {
  name   = "${var.project_name}-atelet-ecr"
  role   = aws_iam_role.objectstore["atelet"].id
  policy = data.aws_iam_policy_document.atelet_ecr.json
}

resource "aws_eks_pod_identity_association" "objectstore" {
  for_each        = aws_iam_role.objectstore
  cluster_name    = aws_eks_cluster.poc.name
  namespace       = "ate-system"
  service_account = each.key
  role_arn        = each.value.arn
  depends_on      = [aws_eks_addon.pod_identity_agent]
}
