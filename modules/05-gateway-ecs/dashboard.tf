# =============================================================================
# OBSERVABILIDAD NATIVA: CLOUDWATCH DASHBOARD PARA CLAUDE APPS GATEWAY
# =============================================================================
# Dashboard 100% serverless, en la capa gratuita de AWS ($0), integrado con
# CloudWatch Logs Insights y metricas nativas de ECS Fargate y ALB Interno.

resource "aws_cloudwatch_dashboard" "gateway" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      # -----------------------------------------------------------------------
      # Fila 1: Encabezado y Accesos Rapidos
      # -----------------------------------------------------------------------
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "##Claude Apps Gateway — Panel de Control y Observabilidad\n**Entorno:** `${var.project_name}` | **Region:** `${var.aws_region}` | **Gateway:** `https://${var.gateway_fqdn}`\nMonitoreo en tiempo real de consumo en USD, modelos Bedrock, latencias, topes mensuales ($10 DevSenior / $5 DevJunior) y salud de ECS Fargate."
        }
      },

      # -----------------------------------------------------------------------
      # Fila 2: Consumo por Desarrollador y Distribucion por Modelo
      # -----------------------------------------------------------------------
      {
        type   = "log"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "Peticiones y Gasto por Desarrollador (Email)"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | filter evt = 'inference' or ispresent(email) | stats count(*) as total_requests, count_distinct(sub) as active_sessions, sum(cost_cents)/100 as spend_usd, avg(ms) as avg_latency_ms by email | sort total_requests desc"
          view    = "table"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title   = "Peticiones por Modelo Anthropic (Bedrock)"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | filter evt = 'inference' | stats count(*) as requests, avg(ms) as avg_latency_ms, max(ms) as max_latency_ms by model | sort requests desc"
          view    = "table"
          stacked = false
        }
      },

      # -----------------------------------------------------------------------
      # Fila 3: Latencias (p50, p90, p99) y Bloqueos de Cuota (429 / spend.blocked)
      # -----------------------------------------------------------------------
      {
        type   = "log"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Latencia de Inferencia en Bedrock (p50, p90, p99 ms)"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | filter evt = 'inference' and ispresent(ms) | stats pct(ms, 50) as p50_ms, pct(ms, 90) as p90_ms, pct(ms, 99) as p99_ms by bin(5m)"
          view    = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title   = "Bloqueos por Limite de Gasto (429 / spend.blocked)"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | filter evt = 'spend.blocked' or status = 429 or @message like /spend.blocked/ | stats count(*) as blocked_count by bin(15m), email, reason | sort blocked_count desc"
          view    = "table"
          stacked = false
        }
      },

      # -----------------------------------------------------------------------
      # Fila 4: Errores Auth / Acceso y Sesiones OIDC
      # -----------------------------------------------------------------------
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "Errores de Autenticacion / Permisos (401 / 403)"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | filter evt = 'auth.denied' or status = 403 or status = 401 | stats count(*) as error_count by bin(15m), reason, path, email | sort error_count desc"
          view    = "table"
          stacked = false
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title   = "Inicios de Sesion OIDC Exitosos (session.mint)"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | filter evt = 'session.mint' | stats count(*) as logins by bin(1h), email, client_ip | sort logins desc"
          view    = "table"
          stacked = false
        }
      },

      # -----------------------------------------------------------------------
      # Fila 5: Metricas de Infraestructura ECS y ALB
      # -----------------------------------------------------------------------
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          title   = "Consumo CPU y Memoria (ECS Fargate)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.gateway.name, "ClusterName", aws_ecs_cluster.main.name, { "label" : "CPU %", "color" : "#ff7f0e" }],
            [".", "MemoryUtilization", ".", ".", ".", ".", { "label" : "Memoria %", "color" : "#1f77b4" }]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          title   = "Trafico y Latencia del ALB Interno"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.internal.arn_suffix, { "stat" : "Sum", "label" : "Peticiones ALB", "color" : "#2ca02c" }],
            [".", "TargetResponseTime", ".", ".", { "stat" : "Average", "label" : "Tiempo Respuesta (s)", "color" : "#d62728", "yAxis" : "right" }]
          ]
          period = 300
        }
      },

      # -----------------------------------------------------------------------
      # Fila 6: Panel de Logs en Vivo
      # -----------------------------------------------------------------------
      {
        type   = "log"
        x      = 0
        y      = 26
        width  = 24
        height = 8
        properties = {
          title   = "📋 Logs en Vivo del Claude Apps Gateway y Prompts de Usuarios"
          region  = var.aws_region
          query   = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | fields @timestamp, evt, email, model, status, ms, prompt, @message | sort @timestamp desc | limit 100"
          view    = "table"
          stacked = false
        }
      }
    ]
  })
}
