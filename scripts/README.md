# Scripts de Automatización (`scripts/`)

En este directorio se encuentran los scripts de automatización del laboratorio:

- [`tf-docs.sh`](./tf-docs.sh): Generador automático de documentación de Terraform y diagramas de arquitectura (SVG).
- [`build_and_push_gateway.sh`](./build_and_push_gateway.sh): Construcción multi-etapa y publicación de la imagen Docker de Claude Apps Gateway en Amazon ECR asumiendo el rol de la Cuenta B.

---

# Guía de Uso: `tf-docs.sh`

`tf-docs.sh` genera de forma automatizada y sincronizada la documentación técnica y los diagramas de dependencias de Terraform tanto para la **raíz del proyecto** como para **cada uno de los submódulos** (`modules/*`).

## 1. Requisitos Previos

Para ejecutar el script se requiere contar con las siguientes herramientas instaladas:

1. **`terraform`** (v1.6.0 o superior).
2. **`dot`** (Graphviz): Necesario para renderizar los grafos en formato vectorial SVG.
   - En Linux (Arch/Manjaro): `sudo pacman -S graphviz`
   - En Ubuntu/Debian: `sudo apt-get install -y graphviz`
3. **`terraform-docs`** o **`docker`**:
   - Si la herramienta `terraform-docs` está en el `$PATH`, se ejecutará de forma nativa.
   - Si no está instalada, el script utiliza automáticamente la imagen oficial Docker `quay.io/terraform-docs/terraform-docs` sin requerir configuración adicional.
4. **Caché de proveedores (`.terraform/providers`)**:
   - Debe haberse ejecutado al menos una vez `terraform init -backend=false` en la raíz del proyecto para poblar los binarios de proveedores (`aws`, `cloudflare`, `random`, etc.).

---

## 2. Modos de Uso

El script es flexible y detecta automáticamente el contexto de ejecución.

### 2.1 Generación completa en lote (Raíz + Todos los módulos)

Por defecto, si se ejecuta desde la raíz del proyecto o con el argumento `all`, documentará el proyecto completo y cada módulo en `modules/*`:

```bash
# Desde la raiz del repositorio
./scripts/tf-docs.sh

# O indicando explicitamente "all"
./scripts/tf-docs.sh all
```

### 2.2 Generar únicamente la raíz del proyecto

Para actualizar únicamente el [`README.md`](../README.md) principal y su gráfico general:

```bash
./scripts/tf-docs.sh root
# o bien
./scripts/tf-docs.sh .
```

### 2.3 Generar un único módulo específico

Puedes pasar el nombre o la ruta relativa del módulo como argumento:

```bash
# Por nombre de carpeta
./scripts/tf-docs.sh 01-organization

# O por ruta relativa
./scripts/tf-docs.sh modules/03-networking-dns
```

### 2.4 Ejecución desde el interior de un módulo

Si te encuentras dentro del directorio de un módulo específico, el script detecta que no estás en la raíz y genera la documentación únicamente para ese módulo:

```bash
cd modules/05-gateway-ecs
../../scripts/tf-docs.sh
```

---

## 3. Comportamiento y Funcionamiento Interno

### 3.1 Preservación del contenido manual (Preámbulo)
- El script examina si el archivo `README.md` objetivo ya existe.
- Si existe, **conserva íntegramente todo el contenido previo a la sección `## Requirements`** (guías, explicaciones, tablas personalizadas, diagramas ASCII).
- Únicamente regenera y reemplaza las secciones generadas por `terraform-docs` (`## Requirements`, `## Providers`, `## Modules`, `## Resources`, `## Inputs`, `## Outputs`) y la sección `## Diagram`.
- Si el `README.md` no existía previamente (como en los módulos nuevos), inyecta automáticamente una cabecera y descripción inicial del módulo en la arquitectura antes de añadir las tablas.

### 3.2 Generación limpia de grafos (`TF_DATA_DIR` temporal)
- Terraform exige inicialización para ejecutar `terraform graph`. Para evitar dejar carpetas `.terraform` o ficheros `.terraform.lock.hcl` huérfanos dentro de cada módulo en Git:
  1. Crea un directorio temporal para `TF_DATA_DIR`.
  2. Inicializa temporalmente con `terraform init -backend=false -plugin-dir="$REPO_ROOT/.terraform/providers"`.
  3. Ejecuta `terraform graph` y lo canaliza a `dot -Tsvg`.
  4. Destruye inmediatamente el directorio temporal y el lockfile efímero.
- Esto garantiza que el árbol de Git permanezca 100% limpio de artefactos innecesarios.

### 3.3 Centralización de diagramas en `media/`
- Todos los diagramas generados se almacenan como archivos vectoriales SVG en la carpeta [`media/`](../media/) en la raíz:
  - `media/claude-gateway-lab_graph.svg` (diagrama global)
  - `media/01-organization_graph.svg`
  - `media/02-identity-cognito_graph.svg`
  - `media/03-networking-dns_graph.svg`
  - `media/04-database_graph.svg`
  - `media/05-gateway-ecs_graph.svg`
- Los enlaces generados en cada `README.md` utilizan rutas relativas correctas (`media/...` en la raíz y `../../media/...` en los módulos) para renderizarse perfectamente en GitHub, GitLab y editores como VS Code.

### 3.4 Idempotencia
- El script es completamente idempotente: puede ejecutarse tantas veces como sea necesario (por ejemplo, en hooks de pre-commit o pipelines de CI/CD) sin duplicar encabezados ni corromper el contenido manual.
