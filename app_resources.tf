resource "aws_ecr_repository" "app" {
  name         = "app"
  force_delete = true
}

resource "random_string" "random" {
  length           = 16
  special          = false
}

resource "aws_ssm_parameter" "ssm_secret" {
  name  = "/supersecret"
  type  = "SecureString"
  value = random_string.random.result

}

resource "docker_image" "this" {
  name = "${aws_ecr_repository.app.repository_url}:v1"

  build { context = "./app" } # Path to our local Dockerfile
}

# * Push our container image to our ECR.
resource "docker_registry_image" "this" {
  keep_remotely = true # Do not delete old images when a new image is pushed
  name          = resource.docker_image.this.name
}




resource "aws_iam_role" "taskexec" {
  name               = "taskexecrole"
  assume_role_policy = <<-EOF
  {
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  inline_policy {
    name   = "ECR"
    policy = <<-EOF
{
"Version": "2012-10-17",
"Statement": [
{
    "Effect": "Allow",
    "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
    ],
    "Resource": "*"
}
]
}
EOF
  }

  inline_policy {
    name   = "SSM"
    policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "ssm:GetParameters"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_ssm_parameter.ssm_secret.arn}"
        ]
      }
    ]
  }
  EOF
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name = "ecsapp"
}

resource "aws_ecs_task_definition" "this" {
	container_definitions = jsonencode([{
		secrets: [
			{ name = "TEST", valueFrom = "${aws_ssm_parameter.ssm_secret.arn}" }
		],
		essential = true,
		image = resource.docker_registry_image.this.name,
		name = "app",
		portMappings = [{ containerPort = 5000 }],
         logConfiguration= {
                logDriver= "awslogs",
                options= {
                    awslogs-group= aws_cloudwatch_log_group.app.name,
                    awslogs-region= var.region,
                    awslogs-create-group= "true",
                    awslogs-stream-prefix= "ecs"
                }
            },
	}])
	cpu = 256
	execution_role_arn = aws_iam_role.taskexec.arn
	family = "apptasks"
	memory = 512
	network_mode = "awsvpc"
	requires_compatibilities = ["FARGATE"]
}

module "app_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "app-sg"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 5000
      to_port                  = 5000
      protocol                 = "tcp"
      description              = "app"
      source_security_group_id = module.alb.security_group_id
    },
  ]

  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
}

resource "aws_ecs_service" "this" {
	cluster = aws_ecs_cluster.this.name
	desired_count = 1
	launch_type = "FARGATE"
	name = "app-service"
	task_definition = resource.aws_ecs_task_definition.this.arn



	load_balancer {
		container_name = "app"
		container_port = 5000
		target_group_arn = module.alb.target_group_arns[0]
	}

	network_configuration {
		security_groups = [module.app_sg.security_group_id]
		subnets = module.vpc.private_subnets
	}
}