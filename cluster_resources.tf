resource "aws_cloudwatch_log_group" "this" {
  name = "ecscluster"
}

resource "aws_ecs_cluster" "this" {
  name = "testcluster"

  configuration {
    execute_command_configuration {
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.this.name
      }
    }
  }
}
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE_SPOT"
  }

}

resource "tls_private_key" "this" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "this" {
  private_key_pem = tls_private_key.this.private_key_pem

  subject {
    common_name  = "testest.com"
    organization = "Test Test"
  }

  validity_period_hours = 100

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "this" {
  private_key      = tls_private_key.this.private_key_pem
  certificate_body = tls_self_signed_cert.this.cert_pem
}


module "alb" {
	source  = "terraform-aws-modules/alb/aws"
	version = "~> 8.4.0"

	load_balancer_type = "application"
	security_groups = [module.vpc.default_security_group_id]
	subnets = module.vpc.public_subnets
	vpc_id = module.vpc.vpc_id

	security_group_rules = {
		ingress_all_http = {
			type        = "ingress"
			from_port   = 80
			to_port     = 80
			protocol    = "TCP"
			description = "HTTP web traffic"
			cidr_blocks = ["0.0.0.0/0"]
		}
		ingress_all_https = {
			type        = "ingress"
			from_port   = 443
			to_port     = 443
			protocol    = "TCP"
			description = "HTTPS web traffic"
			cidr_blocks = ["0.0.0.0/0"]
		}
		egress_all = {
			type        = "egress"
			from_port   = 0
			to_port     = 0
			protocol    = "-1"
			cidr_blocks = ["0.0.0.0/0"]
		}
	}

    https_listeners = [
        {
        port               = 443
        protocol           = "HTTPS"
        certificate_arn    = aws_acm_certificate.this.arn
        target_group_index = 0
        }
    ]

    http_tcp_listeners = [
        {
        port        = 80
        protocol    = "HTTP"
        action_type = "redirect"
        redirect = {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
        }
        }
    ]

	target_groups = [
		{
			backend_port         = 5000
			backend_protocol     = "HTTP"
			target_type          = "ip"
		}
	]
}



output "alb_dns" {

    value = module.alb.lb_dns_name
  
}