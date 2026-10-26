# =============================================================================
# MODULO 03: NETWORKING, CLOUDFLARE DNS, ACM TLS & TAILSCALE SUBNET ROUTER
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# 1. VPC & Subredes (2 Publicas + 2 Privadas Aisladas, Cero NAT Gateways)
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
    Tier = "Public"
  }
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Tier = "Private-Isolated"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Tabla de rutas privada aislada: SIN NAT Gateway por diseno de ahorro de costes ($0/mes en NAT)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-isolated-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# 2. Certificado TLS en AWS ACM + Validacion DNS en Cloudflare
# -----------------------------------------------------------------------------
resource "aws_acm_certificate" "gateway" {
  domain_name = "${var.primary_subdomain}.${var.domain_name}"
  subject_alternative_names = [
    "${var.secondary_subdomain}.${var.domain_name}",
    "${var.observability_subdomain}.${var.domain_name}"
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-gateway-cert"
  }
}

resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.gateway.domain_validation_options : dvo.domain_name => {
      name   = trimsuffix(dvo.resource_record_name, ".")
      record = trimsuffix(dvo.resource_record_value, ".")
      type   = dvo.resource_record_type
    }
  }

  zone_id         = var.cloudflare_zone_id
  name            = each.value.name
  content         = each.value.record
  type            = each.value.type
  ttl             = 60
  proxied         = false
  allow_overwrite = true
  comment         = "Validacion DNS ACM para Claude Apps Gateway (${each.key})"
}

resource "aws_acm_certificate_validation" "gateway" {
  certificate_arn         = aws_acm_certificate.gateway.arn
  validation_record_fqdns = [for record in cloudflare_record.acm_validation : record.hostname]
}

# -----------------------------------------------------------------------------
# 3. Registros CNAME de Acceso Privado en Cloudflare (proxied = false)
# -----------------------------------------------------------------------------
resource "cloudflare_record" "gateway_primary" {
  count = var.create_gateway_dns_records ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = var.primary_subdomain
  type            = "CNAME"
  content         = var.internal_alb_dns_name
  ttl             = 60
  proxied         = false
  allow_overwrite = true
  comment         = "Acceso privado via Tailscale hacia el ALB Interno de Claude Apps Gateway"
}

resource "cloudflare_record" "gateway_secondary" {
  count = var.create_gateway_dns_records ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = var.secondary_subdomain
  type            = "CNAME"
  content         = var.internal_alb_dns_name
  ttl             = 60
  proxied         = false
  allow_overwrite = true
  comment         = "Acceso privado via Tailscale hacia el ALB Interno de Claude Apps Gateway"
}

resource "cloudflare_record" "observability" {
  count = var.create_gateway_dns_records ? 1 : 0

  zone_id         = var.cloudflare_zone_id
  name            = var.observability_subdomain
  type            = "CNAME"
  content         = var.internal_alb_dns_name
  ttl             = 60
  proxied         = false
  allow_overwrite = true
  comment         = "Acceso privado via Tailscale hacia Grafana en el ALB Interno (eyes)"
}

# -----------------------------------------------------------------------------
# 4. Tailscale Subnet Router (EC2 t4g.nano AL2023 ARM64)
# -----------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_security_group" "tailscale_router" {
  name        = "${var.project_name}-tailscale-router-sg"
  description = "Security Group para Tailscale Subnet Router (Cero puertos TCP entrantes desde Internet)"
  vpc_id      = aws_vpc.main.id

  # Sin reglas de ingreso (ingress vacio): Tailscale establece tunel saliente WireGuard/DERP
  egress {
    description = "Trafico hacia la VPC interna (ALB interno y RDS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Salida a Internet para plano de control Tailscale, STUN/DERP y actualizaciones"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-tailscale-router-sg"
  }
}

resource "aws_iam_role" "tailscale_router" {
  name = "${var.project_name}-tailscale-router-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tailscale_ssm" {
  role       = aws_iam_role.tailscale_router.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "tailscale_router" {
  name = "${var.project_name}-tailscale-router-profile"
  role = aws_iam_role.tailscale_router.name
}

resource "aws_instance" "tailscale_router" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = var.tailscale_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.tailscale_router.id]
  iam_instance_profile        = aws_iam_instance_profile.tailscale_router.name
  associate_public_ip_address = true

  # Critico para que EC2 pueda enrutar paquetes cuyo destino no es su propia IP privada
  source_dest_check = false

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/tailscale_userdata.sh.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    vpc_cidr           = var.vpc_cidr
    tailscale_hostname = var.tailscale_hostname
  })

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = "${var.project_name}-tailscale-subnet-router"
  }
}
