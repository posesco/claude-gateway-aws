#!/usr/bin/env python3
"""Render the maintained architecture model as editable draw.io XML and SVG.

Only Python's standard library and the checked-in AWS icons are required.
This is a documentation model, not a Terraform parser or deployment discovery.
"""

import base64
import copy
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "media"
WIDTH, HEIGHT = 1900, 1510
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
INK, GREY, PURPLE, BLUE = "#232f3e", "#5f6b7a", "#8c4fff", "#147dba"
SHAPES, EDGES = [], []


def label(key, x, y, text, size=19, color=INK, bold=False, align="middle"):
    SHAPES.append(dict(kind="text", id=key, x=x, y=y, text=text,
                       size=size, color=color, bold=bold, align=align))


def box(key, x, y, width, height, color=INK, fill="white", rounded=False):
    SHAPES.append(dict(kind="box", id=key, x=x, y=y, w=width, h=height,
                       color=color, fill=fill, rounded=rounded))


def icon(key, x, y, filename, size=64):
    SHAPES.append(dict(kind="icon", id=key, x=x, y=y, w=size, h=size,
                       file=filename))


def service(key, cx, y, filename, title, *details):
    icon(key, cx - 32, y, filename)
    label(key + "-title", cx, y + 89, title, bold=True)
    for i, line in enumerate(details):
        label(f"{key}-detail-{i}", cx, y + 115 + i * 23, line, 17, GREY)


def edge(key, source, target, points, color=INK, dashed=False):
    EDGES.append(dict(id=key, source=source, target=target,
                      points=points, color=color, dashed=dashed))


def model():
    label("title", 45, 39, "Claude Apps Gateway · arquitectura AWS multi-cuenta",
          30, bold=True, align="start")
    label("subtitle", 45, 70,
          "Arquitectura declarada en Terraform · valores por defecto · despliegue no verificado",
          18, GREY, align="start")
    box("identity-account", 320, 105, 1110, 255)
    icon("identity-badge", 332, 117, "AWS-Account_32.svg", 32)
    label("identity-title", 378, 140, "Cuenta A · Management / identidad", 22,
          bold=True, align="start")
    service("organizations", 500, 174, "Arch_AWS-Organizations_64.svg",
            "AWS Organizations", "Gobierno de Cuenta B · global")
    service("cognito", 850, 174, "Arch_Amazon-Cognito_64.svg",
            "Amazon Cognito", "Hosted UI · OIDC · eu-west-1", "Admins / DevSenior / DevJunior")
    service("lambda", 1190, 174, "Arch_AWS-Lambda_64.svg",
            "Lambda pre-token", "Claim groups desde Cognito")
    box("workload-account", 320, 405, 1510, 1025)
    icon("workload-badge", 332, 417, "AWS-Account_32.svg", 32)
    label("workload-title", 378, 441, "Cuenta B · Workload · eu-west-1", 22,
          bold=True, align="start")
    box("vpc", 350, 475, 1110, 710, PURPLE)
    icon("vpc-badge", 362, 487, "Virtual-private-cloud-VPC_32.svg", 32)
    label("vpc-title", 405, 511, "VPC 10.20.0.0/16 · 2 AZ · cero NAT Gateway",
          20, PURPLE, True, "start")
    box("public-subnets", 380, 535, 1050, 310, "#248236", "#f6fbf6")
    label("public-title", 398, 561, "Públicas · 10.20.1.0/24 y 10.20.2.0/24",
          18, "#248236", True, "start")
    box("private-subnets", 380, 925, 1050, 230, "#147dba", "#f5faff")
    label("private-title", 398, 952, "Privadas", 18, BLUE, True, "start")
    label("private-cidr-1", 398, 978, "10.20.11.0/24", 15, BLUE, align="start")
    label("private-cidr-2", 398, 1001, "10.20.12.0/24", 15, BLUE, align="start")
    box("client", 40, 582, 220, 103, rounded=True)
    label("client-title", 150, 613, "Desarrollador", 21, bold=True)
    label("client-cli", 150, 641, "Claude Code + navegador", 17)
    label("client-vpn", 150, 666, "Cliente Tailscale", 17)
    service("router", 520, 595, "Arch_Amazon-EC2_64.svg", "EC2 · Tailscale",
            "Subnet router · t4g.micro", "Anuncia 10.20.0.0/16", "Primera subred pública", "SG sin ingress")
    service("gateway", 870, 595, "Arch_AWS-Fargate_64.svg", "Gateway · ECS Fargate",
            "1 tarea · 0.25 vCPU / 512 MiB", "Init: db-quota-seeder", "Proxy :8080 → gateway :8081",
            "IP pública para salida", "Ingress :8080 solo desde ALB")
    service("observability", 1220, 595, "Arch_AWS-Fargate_64.svg", "Observabilidad · Fargate",
            "1 tarea · 0.5 vCPU / 1 GiB", "Init: dashboard-s3-sync", "Grafana + Loki + Alertmanager",
            "Grafana consulta cuotas en RDS", "Alerta de cuota ≥ 80%")
    service("alb", 620, 985, "Arch_Elastic-Load-Balancing_64.svg", "ALB interno · HTTPS 443",
            "Certificado ACM · 2 AZ", "aidevtool / dev → gateway", "eyes → Grafana :3000")
    service("rds", 1060, 985, "Arch_Amazon-RDS_64.svg", "Amazon RDS PostgreSQL 16",
            "Privado · Single-AZ · db.t4g.micro", "DevSenior $10 / DevJunior $5 al mes", "Gateway + seeder + Grafana · TLS :5432")
    label("services-title", 1655, 511, "Servicios AWS", 21, bold=True)
    label("services-subtitle", 1655, 539, "Fuera de la VPC", 18, GREY)
    service("bedrock", 1655, 595, "Arch_Amazon-Bedrock_64.svg", "Amazon Bedrock",
            "HTTPS 443 · IAM task role", "Endpoint eu-west-1", "Perfiles de inferencia europeos")
    service("cloudwatch", 1655, 808, "Arch_Amazon-CloudWatch_64.svg", "Amazon CloudWatch",
            "Logs ECS · retención 7 días", "Dashboard ECS / ALB", "Métricas + Logs Insights")
    service("sns", 1655, 1010, "Arch_Amazon-Simple-Notification-Service_64.svg",
            "Amazon SNS → email", "Desde Alertmanager · SigV4")
    box("dns", 40, 1000, 220, 119, rounded=True)
    label("dns-title", 150, 1030, "Cloudflare DNS", 21, bold=True)
    label("dns-only", 150, 1058, "CNAME · proxied=false", 17)
    label("dns-validation", 150, 1083, "Validación DNS de ACM", 17)
    label("dns-resolution", 150, 1106, "Resuelve ALB a IP privada", 16)
    icon("igw", 428, 875, "Res_Amazon-VPC_Internet-Gateway_48.svg", 32)
    label("egress", 474, 898, "Salida IGW",
          17, GREY, align="start")
    label("bootstrap-title", 378, 1231,
          "Servicios de soporte · bootstrap ECS, configuración y descubrimiento privado",
          20, bold=True, align="start")
    support = [
        ("ecr", 500, "Arch_Amazon-Elastic-Container-Registry_64.svg", "Amazon ECR", "Imagen del gateway"),
        ("ssm", 730, "Arch_AWS-Systems-Manager_64.svg", "SSM Parameter Store", "gateway.yaml + SQL"),
        ("secrets", 960, "Arch_AWS-Secrets-Manager_64.svg", "Secrets Manager", "Credenciales / claves"),
        ("s3", 1190, "Arch_Amazon-Simple-Storage-Service_64.svg", "Amazon S3", "Provisioning de Grafana"),
        ("cloudmap", 1420, "Arch_AWS-Cloud-Map_64.svg", "AWS Cloud Map", "DNS privado de Loki"),
        ("acm", 1650, "Arch_AWS-Certificate-Manager_64.svg", "AWS ACM", "TLS del ALB")]
    for key, cx, filename, title, detail in support:
        service(key, cx, 1260, filename, title, detail)
    label("legend", 45, 1464, "Línea continua: tráfico de aplicación · Discontinua: OIDC / DNS / telemetría",
          18, GREY, align="start")
    label("legend-subnets", 45, 1492, "Subredes agrupadas por función; no se duplican tareas por AZ.",
          18, GREY, align="start")
    edge("oidc-login", "client", "cognito",
         [(150, 582), (150, 330), (690, 330), (690, 206), (818, 206)], PURPLE, True)
    label("oidc-login-label", 160, 390, "1 · Login OIDC", 17, PURPLE, align="start")
    edge("token-trigger", "cognito", "lambda", [(882, 206), (1158, 206)], PURPLE, True)
    label("trigger-label", 1020, 194, "Pre-token", 16, PURPLE)
    edge("jwks", "gateway", "cognito",
         [(870, 595), (870, 570), (1410, 570), (1410, 385),
          (1010, 385), (1010, 225), (882, 225)], PURPLE, True)
    label("jwks-label", 1140, 375, "OIDC / JWKS · HTTPS", 17, PURPLE)
    edge("tailscale", "client", "router", [(260, 627), (488, 627)])
    label("tailscale-label", 360, 613, "2 · Tailscale", 17)
    edge("router-alb", "router", "alb",
         [(552, 627), (680, 627), (680, 869), (620, 869), (620, 985)])
    label("https-label", 650, 859, "3 · HTTPS 443", 17)
    edge("alb-gateway", "alb", "gateway",
         [(652, 1017), (715, 1017), (715, 627), (838, 627)])
    label("gateway-port", 767, 831, "HTTP :8080", 16, align="start")
    edge("invoke", "gateway", "bedrock",
         [(902, 612), (940, 612), (940, 590), (1555, 590), (1555, 627), (1623, 627)])
    label("bedrock-label", 1210, 553, "5 · Inferencia HTTPS 443", 17)
    edge("quotas", "gateway", "rds",
         [(902, 645), (1020, 645), (1020, 905), (1060, 905), (1060, 985)])
    label("quotas-label", 1160, 899, "4 · Cuotas · TLS :5432", 17)
    edge("logs-loki", "gateway", "observability", [(902, 631), (1188, 631)], BLUE, True)
    label("loki-label", 1050, 621, "Loki :3100", 16, BLUE)
    edge("grafana", "alb", "observability",
         [(652, 1036), (810, 1036), (810, 1160), (1380, 1160),
          (1380, 650), (1252, 650)], BLUE)
    label("grafana-label", 1275, 1180, "eyes → HTTP :3000", 16, BLUE)
    edge("ecs-logs", "observability", "cloudwatch",
         [(1252, 636), (1350, 636), (1350, 840), (1623, 840)], BLUE, True)
    label("ecs-logs-label", 1540, 827, "Logs ECS", 16, BLUE)
    edge("alerts", "observability", "sns",
         [(1252, 617), (1480, 617), (1480, 1042), (1623, 1042)], BLUE, True)
    label("sns-label", 1548, 1031, "Alertas", 16, BLUE)
    edge("dns-cname", "dns", "alb", [(260, 1043), (588, 1043)], GREY, True)
    label("dns-label", 420, 1030, "DNS-only", 16, GREY)


def svg_node(parent, name, **attrs):
    return ET.SubElement(parent, f"{{{SVG}}}{name}",
                         {key.replace("_", "-"): str(value) for key, value in attrs.items()})


def render_svg():
    svg = ET.Element(f"{{{SVG}}}svg", dict(viewBox=f"0 0 {WIDTH} {HEIGHT}",
                     width=str(WIDTH), height=str(HEIGHT), role="img"))
    svg_node(svg, "title").text = "Arquitectura declarada de Claude Apps Gateway en AWS"
    svg_node(svg, "desc").text = "Dos cuentas AWS: identidad Cognito y workload privado vía Tailscale, ALB, Fargate, RDS, Bedrock y observabilidad."
    svg_node(svg, "rect", width=WIDTH, height=HEIGHT, fill="white")
    defs = svg_node(svg, "defs")
    for color in (INK, PURPLE, BLUE, GREY):
        marker = svg_node(defs, "marker", id="arrow" + color[1:], markerWidth=9,
                          markerHeight=9, refX=8, refY=4, orient="auto", markerUnits="userSpaceOnUse")
        svg_node(marker, "path", d="M0,0 L8,4 L0,8 Z", fill=color)
    # Backgrounds first, connectors next, foreground icons and text last.
    for shape in SHAPES:
        if shape["kind"] == "box":
            svg_node(svg, "rect", x=shape["x"], y=shape["y"], width=shape["w"],
                     height=shape["h"], rx=16 if shape["rounded"] else 0,
                     fill=shape["fill"], stroke=shape["color"], stroke_width=2)
    for item in EDGES:
        svg_node(svg, "polyline", points=" ".join(f"{x},{y}" for x, y in item["points"]),
                 fill="none", stroke=item["color"], stroke_width=2,
                 stroke_dasharray="7 5" if item["dashed"] else "none",
                 marker_end="url(#arrow" + item["color"][1:] + ")")
    for shape in SHAPES:
        if shape["kind"] == "text":
            svg_node(svg, "text", x=shape["x"], y=shape["y"], fill=shape["color"],
                     font_family="Arial, Helvetica, sans-serif", font_size=shape["size"],
                     font_weight="700" if shape["bold"] else "400",
                     text_anchor=shape["align"]).text = shape["text"]
        elif shape["kind"] == "icon":
            original = ET.parse(MEDIA / "aws-icons" / shape["file"]).getroot()
            node = copy.deepcopy(original)
            # Prefix resource IDs so repeated Fargate/account icons remain valid SVG.
            for element in node.iter():
                if "id" in element.attrib:
                    element.set("id", shape["id"] + "-" + element.get("id"))
            node.attrib.update(x=str(shape["x"]), y=str(shape["y"]),
                               width=str(shape["w"]), height=str(shape["h"]))
            svg.append(node)
    return svg


def render_drawio():
    mxfile = ET.Element("mxfile", host="app.diagrams.net", version="29.0.0")
    diagram = ET.SubElement(mxfile, "diagram", id="aws-architecture", name="Arquitectura AWS")
    graph = ET.SubElement(diagram, "mxGraphModel", grid="1", gridSize="10", page="1",
                          pageWidth=str(WIDTH), pageHeight=str(HEIGHT), background="#ffffff")
    root = ET.SubElement(graph, "root")
    ET.SubElement(root, "mxCell", id="0")
    ET.SubElement(root, "mxCell", id="1", parent="0")
    for shape in SHAPES:
        kind = shape["kind"]
        x, y = shape["x"], shape["y"]
        width, height = shape.get("w", 0), shape.get("h", 0)
        value = ""
        if kind == "box":
            style = f"rounded={int(shape['rounded'])};fillColor={shape['fill']};strokeColor={shape['color']};strokeWidth=2;"
        elif kind == "icon":
            data = base64.b64encode((MEDIA / "aws-icons" / shape["file"]).read_bytes()).decode()
            style = f"shape=image;imageAspect=0;aspect=fixed;image=data:image/svg+xml,{data};"
        else:
            value = shape["text"]
            width, height = len(value) * shape["size"] * 0.64 + 20, shape["size"] + 10
            x -= {"middle": width / 2, "end": width, "start": 0}[shape["align"]]
            y -= shape["size"] + 2
            align = {"middle": "center", "end": "right", "start": "left"}[shape["align"]]
            style = (f"text;html=0;whiteSpace=nowrap;align={align};verticalAlign=middle;"
                     f"fontFamily=Arial;fontSize={shape['size']};fontColor={shape['color']};"
                     f"fontStyle={int(shape['bold'])};strokeColor=none;fillColor=none;")
        cell = ET.SubElement(root, "mxCell", id=shape["id"], value=value,
                             style=style, vertex="1", parent="1")
        ET.SubElement(cell, "mxGeometry", x=str(x), y=str(y), width=str(width),
                      height=str(height), **{"as": "geometry"})
    terminals = {shape["id"]: shape for shape in SHAPES}
    for item in EDGES:
        style = (f"edgeStyle=none;rounded=0;html=0;endArrow=block;endFill=1;"
                 f"strokeColor={item['color']};strokeWidth=2;dashed={int(item['dashed'])};")
        for terminal, point, anchor in ((item["source"], item["points"][0], "exit"),
                                        (item["target"], item["points"][-1], "entry")):
            node = terminals[terminal]
            x = (point[0] - node["x"]) / node["w"]
            y = (point[1] - node["y"]) / node["h"]
            style += f"{anchor}X={x};{anchor}Y={y};{anchor}Perimeter=0;"
        cell = ET.SubElement(root, "mxCell", id=item["id"], edge="1", parent="1",
                             source=item["source"], target=item["target"], style=style)
        geometry = ET.SubElement(cell, "mxGeometry", relative="1", **{"as": "geometry"})
        points = item["points"]
        for point, role in ((points[0], "sourcePoint"), (points[-1], "targetPoint")):
            ET.SubElement(geometry, "mxPoint", x=str(point[0]), y=str(point[1]), **{"as": role})
        array = ET.SubElement(geometry, "Array", **{"as": "points"})
        for x, y in points[1:-1]:
            ET.SubElement(array, "mxPoint", x=str(x), y=str(y))
    return mxfile


def main():
    model()
    for suffix, document in (("drawio", render_drawio()), ("svg", render_svg())):
        ET.indent(document, space="  ")
        path = MEDIA / f"architecture.{suffix}"
        ET.ElementTree(document).write(path, encoding="utf-8", xml_declaration=True)
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
