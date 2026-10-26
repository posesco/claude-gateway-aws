# Editar y regenerar la arquitectura AWS

[architecture.svg](architecture.svg) es la imagen que muestra el README. [architecture.drawio](architecture.drawio) contiene iconos, textos, límites y conectores editables individualmente en draw.io / diagrams.net. Los dos archivos incluyen los iconos y pueden visualizarse o editarse sin descargarlos de Internet.

## Regeneración local

Desde la raíz del repositorio, con Python 3:

```bash
python3 scripts/generate_architecture.py
```

También se puede ejecutar con la ruta absoluta al script desde cualquier directorio. No requiere paquetes Python, Terraform, credenciales ni acceso AWS. Usa los SVG oficiales versionados en `aws-icons/` y genera ambos formatos de forma determinista.

La topología y las posiciones se mantienen explícitamente en `model()` de [generate_architecture.py](../scripts/generate_architecture.py). **El generador no descubre recursos ni interpreta Terraform**: al cambiar la infraestructura, hay que actualizar este modelo y regenerar. Representa el código y sus valores por defecto, no un despliegue consultado en AWS.

## Edición manual

1. Abre `architecture.drawio` en draw.io Desktop o impórtalo en diagrams.net.
2. Modifica los elementos y guarda el `.drawio`.
3. Exporta como SVG con fondo blanco e imágenes embebidas y sustituye `architecture.svg`. Desactiva formato de texto HTML para mantener compatibilidad con visores de SVG.

**Regenerar sobrescribe ambos archivos**, incluidos los cambios hechos en draw.io. Para conservar una edición manual, no regeneres hasta trasladarla al modelo Python. El SVG es la vista publicada; el `.drawio` es la fuente para edición manual. La exportación e importación se describen en la [documentación oficial de draw.io](https://www.drawio.com/docs/manual/export/export-to-svg/).

## Qué representa

| Área | Fuentes del repositorio |
| --- | --- |
| Cuentas, proveedores y región | [main.tf](../main.tf), [providers.tf](../providers.tf) |
| Cognito y Lambda de grupos | [Identidad](../modules/02-identity-cognito/main.tf), [Lambda](../modules/02-identity-cognito/lambda/pre_token_generation.py) |
| VPC, Tailscale, DNS y ACM | [Red](../modules/03-networking-dns/main.tf), [defaults del router](../modules/03-networking-dns/variables.tf) |
| RDS y cuotas | [Base de datos](../modules/04-database/main.tf), [SQL](../config/seed_quotas.sql.tftpl) |
| Gateway, ALB, ECR, secretos y configuración | [ECS](../modules/05-gateway-ecs/main.tf), [gateway.yaml](../config/gateway.yaml.tftpl) |
| Grafana, Loki, Alertmanager, S3, Cloud Map y SNS | [Observabilidad](../modules/05-gateway-ecs/observability.tf), [dashboard CloudWatch](../modules/05-gateway-ecs/dashboard.tf) |

Las dos AZ corresponden a la red: cada servicio ECS tiene una tarea y RDS es Single-AZ. Las subredes se agrupan por función sin sugerir réplicas de las cargas. El router usa `t4g.micro`, valor por defecto real del módulo; el ASCII anterior del README conserva la referencia histórica a `t4g.nano`.

Cloudflare solo ofrece DNS y validación de ACM; el tráfico de aplicación entra por Tailscale. Bedrock se representa fuera de la VPC con endpoint `eu-west-1` y perfiles europeos, que pueden enrutar inferencia a otras regiones. Los servicios de soporte se agrupan sin dibujar cada llamada de inicialización; S3 almacena provisioning de Grafana, no los logs de Loki. Grafana consulta cuotas en RDS y CloudWatch recibe logs de los contenedores, relaciones señaladas mediante sus etiquetas.

## Iconos oficiales

Los 19 SVG de `aws-icons/` son copias sin modificar del paquete oficial **AWS Architecture Icons, 31 de julio de 2026**, descargado desde la [página de iconos de arquitectura de AWS](https://aws.amazon.com/architecture/icons/).

- [Paquete oficial original](https://d1.awsstatic.com/onedam/marketing-channels/website/public/shared/architecture-icon-release/Icon-package_07312026.5846e92413caa21490223536cc97f1269e44fa92.zip).
- SHA-256 del ZIP: `d2d166c453526471749d520e0db022c459abef759d2946cf2dd1d1c992dc6526`.
- Se conserva solo el subconjunto utilizado. Los iconos y marcas pertenecen a AWS; su uso está sujeto a las condiciones publicadas por AWS, sin aplicarles una licencia nueva.

El generador inserta copias vectoriales en el SVG y datos de imagen en el `.drawio`; no depende de la biblioteca AWS instalada en el editor.
