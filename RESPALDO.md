# Plan de respaldo — VaN3Twin + SUMO-GEO (actualizado 28-ago-2026)

Estado: pasos 1-2 definidos con la vía del **fork** (sin patch).

## Dónde queda cada cosa

| Contenido | Respaldo |
|---|---|
| Código SUMO-GEO (backend/frontend/replay) | GitHub `Pbarbecho/SUMO_GEO`, en **main** (+ Dropbox) |
| Cambios ns-3 (8 ficheros: traci, EVA, SignalInfo, escenarios) | GitHub **fork `Pbarbecho/VaN3Twin`**, en **master** |
| Stack Docker + manuales + práctica + img + tools | GitHub `Pbarbecho/van3twin-docker` (este repo) |
| Imagen van3twin:jammy (ns-3 compilado) | Docker Hub (opcional) |
| Volumen con el build ya compilado | Tarball local en `backups/` |

## Paso 1 — SUMO_GEO → GitHub (directo en main)

```bash
cd ~/Dropbox/Mac/Documents/SUMO_GEO
git checkout main                # o master, la rama por defecto del repo
git add -A
git commit -m "Integración VaN3Twin: remote multi-cliente + replay pcap V2X"
git push origin main
```

(Si ya se creó y subió la rama `van3twin-replay`: `git checkout main &&
git merge van3twin-replay && git push origin main`.)

## Paso 2 — ns-3 → fork, directo en master

Fork de `DriveX-devs/VaN3Twin` en GitHub; en el contenedor:

```bash
cd ~/VaN3Twin/ns-3-dev
git add -u src/                  # los 8 ficheros modificados
git -c user.name="Pablo Barbecho" -c user.email="pablo.barbecho@ucuenca.edu.ec" \
    commit -m "Integracion SUMO-GEO: TraCI multi-cliente, --num-traci-clients, RSSI SignalInfo"
git remote add fork https://github.com/Pbarbecho/VaN3Twin.git
git push fork master             # auth: usuario + token (scope repo)
```

(Si ya se hizo el commit en la rama `integracion-sumo-geo`:
`git checkout master && git merge integracion-sumo-geo && git push fork master`
— es fast-forward, sin conflictos.)

Con todo en master, **replicar = clonar el fork tal cual** (en Linux o
contenedor). **Nunca clonar en una carpeta APFS normal del Mac para
compilar** (colisión de mayúsculas ActionID/ActionId, BOOLEAN/boolean).

## Paso 3 — Este directorio → GitHub

El `.gitignore` ya excluye el espejo `VaN3Twin/`, los `.pcap` y `backups/`.
Entra todo lo demás: Dockerfile, compose unificado, la carpeta
"Intergracion SUMO 3D WEB VAN3TWIN" (manuales, práctica, contextos, img/,
tools/) y `results/signal-rx.csv` si existe.

```bash
cd ~/van3twin-docker
git init && git add -A
git commit -m "Stack Docker VaN3Twin + visor SUMO-GEO (profile visor) + docs y práctica V2X"
# crear repo vacío en github.com (van3twin-docker, privado) y:
git remote add origin git@github.com:Pbarbecho/van3twin-docker.git
git push -u origin main
```

## Paso 4 — (Opcional) Imagen a Docker Hub y build reproducible desde el fork

```bash
docker login
docker tag van3twin:jammy pbarbecho/van3twin:jammy-arm64
docker push pbarbecho/van3twin:jammy-arm64      # 10-15 GB; es arm64 (Apple Silicon)
docker images | grep backend                    # nombre real de la imagen del visor
docker tag <imagen-backend> pbarbecho/sumo-geo-backend:van3twin
docker push pbarbecho/sumo-geo-backend:van3twin
```

Reproducibilidad futura sin Docker Hub: con los parches ya en **master** del
fork, basta cambiar la URL del clone en el Dockerfile a
`https://github.com/Pbarbecho/VaN3Twin.git` (el `VAN3TWIN_REF: master` por
defecto ya vale) y reconstruir: la imagen sale con la integración incluida.
No es necesario hoy: solo si se reconstruye desde cero.

## Paso 5 — Tarball del volumen (protege el build compilado ante `down -v`)

```bash
mkdir -p ~/van3twin-docker/backups
docker run --rm -v van3twin_ns3-workspace:/src -v ~/van3twin-docker/backups:/dst \
  alpine sh -c 'cd /src && tar czf /dst/ns3-workspace-$(date +%F).tgz .'
```

~4-6 GB. Copiarlo también fuera del Mac (disco externo / Drive). Restaurar:
crear el volumen vacío y `tar xzf` dentro con el mismo patrón de contenedor.

## Paso 6 — Verificación

1. Web: rama `integracion-sumo-geo` visible en `Pbarbecho/VaN3Twin` con los 8 ficheros.
2. Web: rama `van3twin-replay` en `Pbarbecho/SUMO_GEO`.
3. `git clone` de `van3twin-docker` en un dir temporal: compose + docs + img presentes.
4. `ls -lh backups/` muestra el tarball con fecha de hoy.
