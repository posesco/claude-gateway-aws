#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
MEDIA_DIR="$REPO_ROOT/media"
PROVIDERS_DIR="$REPO_ROOT/.terraform/providers"

mkdir -p "$MEDIA_DIR"

# Helper function to get default preamble for new module READMEs
get_module_preamble() {
  local mod_name="$1"
  case "$mod_name" in
    01-organization)
      cat << 'EOF'
# Módulo: AWS Organizations (`modules/01-organization`)

Gestiona la cuenta miembro de Workload (`aws_organizations_account`) dentro del AWS Organization del laboratorio, o reutiliza una cuenta existente, configurando el rol de administración cruzada `OrganizationAccountAccessRole`.

---
EOF
      ;;
    02-identity-cognito)
      cat << 'EOF'
# Módulo: Identidad y Autenticación OIDC (`modules/02-identity-cognito`)

Configura el User Pool de Amazon Cognito en la Cuenta de Identidad (Cuenta A), los grupos de usuarios (`claude-gateway-admins`, `DevSenior`, `DevJunior`), los usuarios iniciales del laboratorio y la función Lambda Pre-Token Generation en Python encargada de inyectar el claim `groups` en el ID Token JWT para el Claude Apps Gateway.

---
EOF
      ;;
    03-networking-dns)
      cat << 'EOF'
# Módulo: Redes, DNS y Acceso Seguro (`modules/03-networking-dns`)

Despliega la VPC privada `10.20.0.0/16` con subredes públicas y privadas aisladas (con coste $0 en NAT Gateways), el túnel WireGuard mediante Tailscale Subnet Router en EC2 AL2023 (`t4g.micro`), el certificado SSL/TLS en AWS ACM y los registros DNS privados en Cloudflare apuntando al Balanceador de Carga Interno (ALB).

---
EOF
      ;;
    04-database)
      cat << 'EOF'
# Módulo: Base de Datos y Secretos (`modules/04-database`)

Aprovisiona la instancia de Amazon RDS PostgreSQL 16 (`db.t4g.micro`) en subredes privadas con coste optimizado para el laboratorio, junto con los grupos de subredes, grupos de seguridad y el secreto en AWS Secrets Manager con la URL de conexión cifrada.

---
EOF
      ;;
    05-gateway-ecs)
      cat << 'EOF'
# Módulo: Claude Apps Gateway en ECS Fargate y Observabilidad (`modules/05-gateway-ecs`)

Despliega el servicio principal de Claude Apps Gateway sobre Amazon ECS Fargate y Application Load Balancer (ALB) Interno con terminación TLS, el contenedor inicial de seeding de cuotas en PostgreSQL, el proxy transparente para inspección de prompts hacia Loki, y el stack de observabilidad privado (Grafana, Loki, Alertmanager con alertas SNS al 80% de consumo y Dashboard en CloudWatch).

---
EOF
      ;;
    *)
      cat << EOF
# Módulo: ${mod_name}

Documentación generada automáticamente para el módulo \`${mod_name}\`.

---
EOF
      ;;
  esac
}

generate_docs() {
  local target_dir="$1"
  local is_root=false
  
  # Resolve target directory to absolute path
  target_dir="$(cd "$target_dir" && pwd)"

  if [ "$target_dir" = "$REPO_ROOT" ]; then
    is_root=true
    local module_name="claude-gateway-lab"
    local graph_file="claude-gateway-lab_graph.svg"
  else
    local module_name="$(basename "$target_dir")"
    local graph_file="${module_name}_graph.svg"
  fi

  echo "============================================================"
  echo "Generating documentation and diagram for: $module_name"
  echo "Path: $target_dir"
  echo "============================================================"

  # 1. Generate terraform-docs markdown into temporary file
  local tmp_docs
  tmp_docs="$(mktemp)"

  if command -v terraform-docs >/dev/null 2>&1; then
    terraform-docs markdown "$target_dir" > "$tmp_docs"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm \
      --volume "$target_dir:/terraform-docs" \
      -u "$(id -u)" \
      quay.io/terraform-docs/terraform-docs \
      markdown /terraform-docs > "$tmp_docs"
  else
    echo "Error: Neither 'terraform-docs' CLI nor 'docker' is available." >&2
    rm -f "$tmp_docs"
    return 1
  fi

  # 2. Update or create README.md preserving any preamble before ## Requirements
  local readme_file="$target_dir/README.md"
  if [ -f "$readme_file" ]; then
    local preamble
    preamble="$(awk '/^## Requirements/{exit} {print}' "$readme_file" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')"

    if [ -n "$preamble" ]; then
      echo "Preserving existing content before '## Requirements' in $readme_file"
      local tf_section
      tf_section="$(awk '/^## Requirements/{found=1} found{print}' "$tmp_docs")"
      if [ -z "$tf_section" ]; then
        tf_section="$(cat "$tmp_docs")"
      fi

      {
        printf '%s\n\n' "$preamble"
        printf '%s\n' "$tf_section"
      } > "$readme_file"
    else
      echo "Overwriting $readme_file with fresh terraform-docs"
      cp "$tmp_docs" "$readme_file"
    fi
  else
    echo "Creating new $readme_file with default module preamble"
    local default_preamble
    default_preamble="$(get_module_preamble "$module_name")"
    {
      printf '%s\n\n' "$default_preamble"
      cat "$tmp_docs"
    } > "$readme_file"
  fi

  rm -f "$tmp_docs"

  # 3. Generate Terraform Graphviz SVG diagram
  if command -v dot >/dev/null 2>&1; then
    echo "Generating architecture graph: $MEDIA_DIR/$graph_file"
    if [ "$is_root" = true ]; then
      terraform -chdir="$target_dir" graph | dot -Tsvg > "$MEDIA_DIR/$graph_file"
    else
      local tmp_tf
      tmp_tf="$(mktemp -d)"
      if [ -d "$PROVIDERS_DIR" ]; then
        TF_DATA_DIR="$tmp_tf" terraform -chdir="$target_dir" init -backend=false -plugin-dir="$PROVIDERS_DIR" >/dev/null 2>&1 || true
      else
        TF_DATA_DIR="$tmp_tf" terraform -chdir="$target_dir" init -backend=false >/dev/null 2>&1 || true
      fi
      TF_DATA_DIR="$tmp_tf" terraform -chdir="$target_dir" graph | dot -Tsvg > "$MEDIA_DIR/$graph_file"
      rm -rf "$tmp_tf" "$target_dir/.terraform.lock.hcl"
    fi

    # 4. Append Diagram section to README.md
    local relative_media_path
    relative_media_path="$(realpath --relative-to="$target_dir" "$MEDIA_DIR")"

    cat >> "$readme_file" << EOF

## Diagram

![Terraform Graph](${relative_media_path}/${graph_file})
EOF
    echo "Updated $readme_file with Diagram section."
  else
    echo "Warning: 'dot' (Graphviz) not found in PATH; skipping graph generation."
  fi

  echo "Successfully documented $module_name"
  echo ""
}

# Main routing
main() {
  local target="${1:-default}"

  case "$target" in
    all)
      generate_docs "$REPO_ROOT"
      for mod_dir in "$REPO_ROOT"/modules/*; do
        if [ -d "$mod_dir" ]; then
          generate_docs "$mod_dir"
        fi
      done
      ;;
    root|.)
      generate_docs "$REPO_ROOT"
      ;;
    default)
      local current_dir
      current_dir="$(pwd)"
      if [ "$current_dir" = "$REPO_ROOT" ]; then
        generate_docs "$REPO_ROOT"
        for mod_dir in "$REPO_ROOT"/modules/*; do
          if [ -d "$mod_dir" ]; then
            generate_docs "$mod_dir"
          fi
        done
      else
        # If run inside a specific module directory
        generate_docs "$current_dir"
      fi
      ;;
    *)
      # Path provided as argument
      if [ -d "$target" ]; then
        generate_docs "$target"
      elif [ -d "$REPO_ROOT/modules/$target" ]; then
        generate_docs "$REPO_ROOT/modules/$target"
      elif [ -d "$REPO_ROOT/$target" ]; then
        generate_docs "$REPO_ROOT/$target"
      else
        echo "Error: Directory '$target' not found." >&2
        echo "Usage: $0 [all | root | <path-to-module>]" >&2
        exit 1
      fi
      ;;
  esac
}

main "$@"
