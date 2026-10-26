# Observabilidad y Monitorización de Claude Apps Gateway (`https://eyes.midominio.com/`)

Este directorio contiene las definiciones declarativas y de auto-aprovisionamiento del stack privado de observabilidad en ECS Fargate para `claude-gateway-lab` (Grafana 13, Loki 3 y Alertmanager 0.34), sincronizadas automáticamente hacia Amazon S3 y montadas en volúmenes compartidos.

---

## 1. Estructura del Directorio `monitoring/`

```text
monitoring/
├── README.md                              # Guía del stack de observabilidad (ECS Eyes + CloudWatch)
├── alertmanager/
│   └── alertmanager.yml.tftpl             # Plantilla de configuración de Alertmanager (renderizada con ARN SNS, Región y FQDN)
└── grafana/
    ├── claude-gateway-dashboard.json      # Dashboard JSON de Grafana (Cuotas SQL + Prompts/Logs en Loki)
    ├── entrypoint.sh                      # Script ejecutable de arranque para Grafana (parseo de DB URL y montaje de configs)
    └── provisioning/                      # Configuraciones YAML de auto-aprovisionamiento nativo de Grafana
        ├── alerting/
        │   └── quota_80_alert.yaml        # Contact point hacia Alertmanager y regla de alerta al >=80% de cuota mensual
        ├── dashboards/
        │   └── default.yaml               # Proveedor de dashboards desde /var/lib/grafana/dashboards
        └── datasources/
            └── all.yaml                   # Datasources PostgreSQL (con variables de entorno), Loki y Alertmanager
```

---

## 2. Stack en ECS Fargate: Grafana + Loki + Alertmanager (`https://eyes.midominio.com/`)

El módulo `05-gateway-ecs` ([observability.tf](../modules/05-gateway-ecs/observability.tf)) despliega el servicio ECS Fargate `claude-gateway-lab-observability-service` expuesto exclusivamente a través del **ALB Interno** cuando **Tailscale** está activo:

- **URL de Acceso Privado:** `https://eyes.midominio.com/` (o la definida en `var.observability_subdomain.var.domain_name`)
- **Credenciales por defecto:** Usuario `admin` / Contraseña definida en `var.grafana_admin_password`.

### Sincronización Declarativa vía S3 (`dashboard-s3-sync`):
El bucket S3 privado `aws_s3_bucket.grafana_dashboards` actúa como repositorio central de configuración y paneles:
- `dashboards/`: Contiene `claude-gateway-dashboard.json`.
- `config/`: Contiene la configuración renderizada de Alertmanager (`config/alertmanager/alertmanager.yml`), los archivos de aprovisionamiento YAML de Grafana (`config/grafana/provisioning/**/*.yaml`) y el script de arranque (`config/grafana/entrypoint.sh`).
- `gateway/`: Contiene `gateway.yaml` y `seed_quotas.sql` renderizados; la tarea Gateway los descarga mediante `gateway-config-sync` a su propio volumen antes del seeding y del servidor.

Al arrancar la tarea ECS Fargate:
1. El contenedor `dashboard-s3-sync` (`public.ecr.aws/aws-cli/aws-cli:latest`) sincroniza `s3://<bucket>/dashboards` hacia `/dashboards` (volumen `grafana-dashboards`) y `s3://<bucket>/config` hacia `/etc/observability` (volumen `observability-config`), aplicando permisos de lectura/ejecución (`chmod -R a+rX`).
2. Los hashes `DASHBOARD_S3_ETAG` y `CONFIG_S3_ETAG` en la definición de la tarea fuerzan un despliegue sin downtime (*rolling deployment*) en ECS cada vez que se modifica cualquier archivo en `monitoring/`.

### Arquitectura de Contenedores en la Tarea ECS (`claude-gateway-lab-observability`):

1. **`dashboard-s3-sync` (`initContainer` - `public.ecr.aws/aws-cli/aws-cli:latest`):**
   - Descarga dashboards y configuraciones desde S3 antes de inicializar los servicios dependientes.
2. **`loki` (`grafana/loki:3.7.9` en `:3100`):**
   - Registrado en AWS Cloud Map como `loki.claude-gateway-lab.internal:3100` (con `deregistration_delay = 15` en los Target Groups del ALB para drenado rápido en despliegues).
   - Recibe desde el proxy del Gateway ([`docker/gateway_proxy_loki.py`](../docker/gateway_proxy_loki.py)) tanto los prompts enviados por los desarrolladores a los modelos (`evt = "user.prompt"`, soportando payloads de hasta 4 MB sobre conexiones HTTP/1.1 Keep-Alive, descompresión `gzip`/`chunked`, correlación `sub -> email`, limpieza automática de etiquetas `<system-reminder>` y `<session>` con deduplicación de 30s) como todos los eventos de `claude gateway` (`inference`, `session.mint`, `spend.blocked`, `auth.denied`, `gateway.info`).
   - **Multi-IP Cloud Map Push + Replay Buffer (`loki_history`):** El proxy resuelve todas las IPs A-record activas de `loki.claude-gateway-lab.internal` en cada envío y mantiene un buffer circular en memoria (`loki_history`, últimos 500 eventos) que se re-sincroniza automáticamente (cada $\le 15\text{ s}$) hacia cualquier nueva IP de Loki detectada tras un rolling update o reinicio de contenedor en ECS.
3. **`alertmanager` (`prom/alertmanager:v0.34.1` en `:9093`):**
   - Inicia tras `dashboard-s3-sync` apuntando directamente a `/etc/observability/alertmanager/alertmanager.yml`.
   - Configurado con `sns_configs` (autenticación IAM SigV4 nativa del Task Role) para publicar alertas en el tópico SNS `claude-gateway-lab-quota-alerts`, suscrito al correo configurado en `var.alert_email`.
5. **`grafana` (`grafana/grafana:13.2.4` en `:3000`):**
   - Ejecuta como punto de entrada `/bin/sh /etc/observability/grafana/entrypoint.sh`, el cual:
     1. Parsea la URL de PostgreSQL inyectada por Secrets Manager (`GATEWAY_POSTGRES_URL`) y exporta las variables `PG_HOSTPORT`, `PG_USER`, `PG_PASS` y `PG_DB`.
     2. Copia los archivos de aprovisionamiento desde `/etc/observability/grafana/provisioning/` a `/etc/grafana/provisioning/`.
     3. Sustituye literalmente los placeholders `${PG_*}` en `/etc/grafana/provisioning/datasources/*.yaml` mediante `awk` (`index`/`substr`), inyectando los valores reales sin depender de macros ni colisionar con caracteres especiales (`&`, `/`, `\`).
     4. Invoca `exec /run.sh "$@"`.
   - Carga de forma nativa los datasources `ClaudeGatewayPostgres` (con `jsonData.database`, `version: 2` y `editable: true` para compatibilidad estricta con Grafana 13), `ClaudeGatewayLoki` (`http://localhost:3100`) y `ClaudeGatewayAlertmanager` (`http://localhost:9093`).
   - Carga la regla de alerta **`claude_quota_80_pct_rule`**, evaluando en PostgreSQL si algún usuario supera el **80% de su cuota mensual** ($8.00 en `DevSenior` / $4.00 en `DevJunior`) para notificar a Alertmanager $\rightarrow$ AWS SNS $\rightarrow$ `var.alert_email`.

---

## 3. Edición y Exportación del Dashboard de Grafana

Cuando modifiques paneles o agregues métricas directamente en la interfaz web de Grafana:
1. Entra a `https://eyes.midominio.com/` (con tu FQDN de observabilidad) con Tailscale activo.
2. Abre el dashboard y haz clic en el icono de engranaje **⚙️ (Dashboard settings)**.
3. En el menú lateral izquierdo, haz clic en **JSON Model**.
4. Copia el JSON completo y pégalo en [monitoring/grafana/claude-gateway-dashboard.json](grafana/claude-gateway-dashboard.json) (asegúrate de mantener `"uid": "claude-gateway-main"` e `"id": null`).
5. Ejecuta `terraform apply`. Terraform detectará el cambio de `filemd5()` en `aws_s3_object.claude_gateway_dashboard`, subirá el archivo a S3 y redesplegará la tarea ECS automáticamente (`DASHBOARD_S3_ETAG`).

---

## 4. Panel Nativo en Amazon CloudWatch (`claude-gateway-lab-overview`)

Además de Grafana en ECS, el módulo `05-gateway-ecs` ([dashboard.tf](../modules/05-gateway-ecs/dashboard.tf)) despliega sin coste adicional ($0 en capa gratuita de AWS) un CloudWatch Dashboard con **9 paneles** de CloudWatch Logs Insights (incluyendo el visor de **Logs en Vivo y Prompts de Usuarios**) y métricas de ECS/ALB.

Para obtener el enlace directo a la consola de AWS:
```bash
terraform output cloudwatch_dashboard_url
```
