#!/usr/bin/env bash
# OBSOLETO (25-ago-2026): el espejo del Mac fue retirado del docker-compose.yml.
# El código se edita directamente en el volumen, dentro del contenedor:
#   docker compose exec van3twin bash    # nano/vim, o VS Code Dev Containers
#   ./ns3 build                          # tras editar C++
# Este script y la carpeta ./VaN3Twin ya no se usan (puedes borrarlos).
echo "OBSOLETO: edita directamente en el contenedor (docker compose exec van3twin bash) y usa ./ns3 build."
exit 1
