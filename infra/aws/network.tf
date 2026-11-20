# The tasks run in the default VPC with a public IP, so they can download the MIMIT files
# without a NAT gateway (which would cost more than the whole pipeline).
# Trade-off: in a company you would use private subnets + NAT or VPC endpoints.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "tasks" {
  name        = "${local.name}-tasks"
  description = "Pipeline tasks: outbound traffic only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Outbound HTTPS and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
