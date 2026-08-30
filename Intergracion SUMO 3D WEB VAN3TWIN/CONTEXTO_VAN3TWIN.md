# Contexto del proyecto VaN3Twin (stack Docker en macOS)

> Contexto de trabajo para la migración/integración con SUMO_GEO.
> Complementa `GUIA_INTEGRACION_SUMO_GEO.md` y `CONTEXTO_SUMO_GEO.md`.
> Fuente: `VaN3Twin_Docker_macOS.tex/pdf`. Stack local: `~/van3twin-docker` (Dockerfile + docker-compose.yml + results/).

## Qué es

VaN3Twin (evolución de **ms-van3t**) es un conjunto de módulos para **ns-3** (fork 5G-LENA de CTTC, tag `ns-3-dev-v2x-v0.2` + módulo `nr` rama `nr-v2x-dev`) que simula comunicaciones V2X con pila **ETSI ITS-G5 completa** (CAM/DENM/CPM/VAM/IVIM con ASN.1 real, DCC, facilities) sobre tecnología de acceso conmutable: **802.11p, LTE, C-V2X Modo 4, NR-V2X**. La movilidad la aporta **SUMO** acoplado por **TraCI**. Licencia GPL-2.0.

Módulos principales en `src/`: `automotive` (pila ETSI + ejemplos + mapas SUMO; requiere OpenSSL y OpenCV), `traci`/`traci-applications` (cliente TraCI ns-3↔SUMO), `cv2x`, `nr`, `gps-tc`, `carla` (gRPC), `sionna`, `vehicle-visualizer` (web Node.js, UDP interno 48110).

## El stack Docker (macOS Apple Silicon)

- Imagen **`van3twin:jammy`**: ubuntu:22.04 **arm64** nativo, build completo dentro de la imagen (~10–15 GB). Capas: toolchain+deps apt → **SUMO 1.12.0 (apt Ubuntu, no PPA)** → gRPC 1.60.0 desde fuente + NetAnim + soporte pybindgen → usuario `vanet` (no root, sudo) → clon VaN3Twin + `sandbox_builder.sh` (no interactivo, sin `install-dependencies`) → `./ns3 configure --build-profile=optimized --enable-examples --disable-python --disable-werror` + `./ns3 build`.
- Proyecto compose **`van3twin`** → contenedor `van3twin`, volumen **`van3twin_ns3-workspace`** (árbol `/home/vanet/VaN3Twin`, persiste ediciones/builds; `down -v` lo borra), red **`van3twin_default`**. `working_dir` = `ns-3-dev`.
- Árbol de código: `/home/vanet/VaN3Twin/ns-3-dev` (en el volumen). En el compose de SUMO-GEO el volumen se monta como `/ns3` (RO).
- GUI por **VNC**: Xvfb `:99` + fluxbox + x11vnc; Mac: `open vnc://127.0.0.1:5901`. Alternativa XQuartz opcional.
- **Puertos**: 8080 (vehicle-visualizer web), 5901→5900 (VNC). El TraCI **1338** NO se publica: SUMO escucha en `0.0.0.0` y es alcanzable por la red Docker interna.
- PyViz NO disponible (bindings no compilan con los parches); alternativas: NetAnim (viene parcheado en `v2v-simple-cam-exchange-80211p`, genera `v2v-cam-exchange-anim.xml`) y Wireshark sobre los `.pcap` (GeoNetworking 0x8947 → BTP → CAM/DENM; filtros `gnw`, `btpb`, `its`).
- Limitaciones Mac/Docker: CARLA no ejecutable (x86_64+GPU NVIDIA; el módulo sí compila), modo emulación `v2x-emulator` inviable (sin NIC real), Sionna via servidor nativo en el Mac (CPU/LLVM) por UDP.

## Diseño vigente (25-ago-2026): solo volumen nombrado

Tras el hallazgo del filesystem (ver más abajo), el compose usa únicamente el volumen nombrado `ns3-workspace:/home/vanet/VaN3Twin` (donde se compila y **se edita directamente**: `docker compose exec van3twin bash` + nano/vim, o VS Code Dev Containers adjuntado al contenedor) y `./results` como salida. El espejo del Mac y `sync-mac-edits.sh` fueron **retirados** el mismo día a petición del usuario; la carpeta `~/van3twin-docker/VaN3Twin` quedó sin uso (es la copia dañada por APFS — Claude ya no debe editarla; para leer código de referencia sirve, sabiendo que los pares con colisión de mayúsculas están corruptos). Ediciones vivas en el volumen: `traci-client.cc` (setOrder + NS_OBJECT_ENSURE_REGISTERED), EVA con `--num-traci-clients`, simple-cam con NetAnim, CMakeLists de ejemplos. **Backup**: las ediciones solo existen en el volumen (`down -v` las borra) → commit con el git interno del árbol o exportar a `~/results`. vehicle-visualizer se publica en **8080** (el 8081 queda para el frontend SUMO-GEO). **Compose unificado (25-ago, tarde):** los servicios del visor SUMO-GEO (`backend`/`frontend`) están en este mismo compose bajo el profile `visor` — `docker compose --profile visor up -d` levanta todo; sin `--profile` solo van3twin.

## Uso diario

```bash
cd ~/van3twin-docker && docker compose up -d
docker compose exec van3twin bash          # aterriza en ns-3-dev
./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false"   # headless
./ns3 build                                 # recompilación incremental (persiste en el volumen)
cp resultados.csv ~/results/                # bind mount → ~/van3twin-docker/results
```

Ojo: el nombre CLI del ejemplo EVA aparece como `v2v-emergencyVehicleAlert-80211p` en la doc Docker y como `v2v-emergency-vehicle-alert-80211p` en la guía de integración — verificar con `./ns3 run --list` (los targets ns-3 suelen usar kebab-case).

## Acoplamiento TraCI (lo relevante para la migración)

- Cliente TraCI de ns-3: `src/traci/model/traci-client.cc`. **Nunca llama a `setOrder()`** (la API sí lo implementa: `sumo-TraCIAPI.cc:87`). Sin `setOrder`, SUMO multi-cliente se bloquea.
- ns-3 lanza SUMO él mismo con `--remote-port` = `ns3::TraciClient::SumoPort` (**default 1338**) y `--step-length <SynchInterval>` (pasos finos, p. ej. 0.1 s) y `--quit-on-end` (al terminar, SUMO muere y el visor pierde conexión: esperado).
- **Correcciones sobre la guía (verificadas 25-ago):**
  1. El EVA fija `SumoPort=3400` (línea 217) — el default 1338 NO aplica → `APP_SUMO_PORT=3400` en SUMO-GEO.
  2. El EVA sobrescribe `SumoAdditionalCmdOptions` con una variable local (línea 230) → la vía `--ns3::TraciClient::...` por CLI no sirve. Se añadió al ejemplo el flag `--num-traci-clients=N` que concatena `--num-clients N` a las opciones de SUMO.
  3. Se añadió `NS_OBJECT_ENSURE_REGISTERED(TraciClient)` en `traci-client.cc` (sin ello, los atributos `--ns3::TraciClient::*` por CLI abortan con "Invalid command-line arguments").
  4. El `./ns3 run` de este fork parte la cadena por espacios sin respetar comillas → flags sin espacios internos.
  5. `traci-client.cc:256` llama a `GetFreePort(m_sumoPort)`: si el puerto anterior sigue en TIME_WAIT (≈60 s tras cada corrida), SUMO arranca en 3401, 3402… → el backend SUMO-GEO escanea `3400..3410` (`APP_SUMO_PORT_SCAN`).
  Comando correcto (nombre camelCase confirmado):
  ```bash
  ./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true --num-traci-clients=2"
  ```
  Procedimiento operativo completo: `MANUAL_SIMULACION_VAN3TWIN_SUMO_GEO.md`.
- **Parche Paso 1 (guía)**: tras `TraCIAPI::connect("localhost", m_sumoPort)` (~línea 282), añadir `setOrder(1)` condicionado a que `m_sumoAddCmdOpt` contenga `--num-clients`. Recompilar con `./ns3 build` (persiste en el volumen; opción permanente: capa `RUN` en el Dockerfile).
- Hechos validados: lockstep sin deadlock (cliente 1 pasos finos + cliente 2 objetivo absoluto grueso); el handshake del cliente 1 **se bloquea** hasta que conecta el cliente 2 (ns-3 "espera" hasta abrir el visor); `setOrder(1)` es inocuo con un solo cliente.

## Ejemplo objetivo: EVA (Emergency Vehicle Alert) 802.11p

- Mapa real (zona de Turín): `src/automotive/examples/sumo_files_v2v_map/map.net.xml` — misma geometría que debe leer el backend SUMO-GEO (`APP_NET_FILE=/ns3/ns-3-dev/src/automotive/examples/sumo_files_v2v_map/map.net.xml`).
- 7–8 vehículos; flags usados: `--sumo-gui=false --met-sup=true`.
- Visores complementarios: **SUMO-GEO :8081** = verdad terreno 3D; **vehicle-visualizer :8080** = verdad terreno 2D nativa; **GEO SUMO WEB de la práctica :8090** = percepción por radio (CAMs por receptor).

## Hallazgo crítico (25-ago-2026): el árbol NO puede compilarse desde APFS case-insensitive

El repo tiene pares de ficheros que solo difieren en mayúsculas (core `boolean.h`/`integer.h` vs ASN.1 `BOOLEAN.h`/`INTEGER.h`; `ActionID.*`/`ActionId.*`; `IVILaneWidth`/`IviLaneWidth`; …). Al bind-montear el árbol desde una carpeta APFS normal (case-insensitive): (1) cada par colapsa en un solo fichero — la copia del Mac ya tiene fuentes ASN.1 machacadas (visibles en `git status`); (2) un mismo TU (p. ej. `traci-client.cc`) necesita `<ns3/integer.h>` del core **y** `"INTEGER.h"` de ASN.1 a la vez → irresoluble. Síntoma observado: error de compilación con sugerencia `MakeTupleChecker` (el `boolean.h` incluido era el ASN.1). Conclusión: compilar solo desde el **volumen nombrado** de Docker o desde un volumen **APFS case-sensitive** con el árbol restaurado vía `git checkout`.

## Versiones (crítico)

Contenedor van3twin: **SUMO 1.12.0** (apt Ubuntu 22.04, rango probado del framework 1.6–1.18). Cualquier cliente TraCI que se conecte (backend SUMO-GEO) debe pinar **traci==1.12.0 / sumolib==1.12.0**. Si algún día se actualiza el SUMO del contenedor, actualizar esos pines.
