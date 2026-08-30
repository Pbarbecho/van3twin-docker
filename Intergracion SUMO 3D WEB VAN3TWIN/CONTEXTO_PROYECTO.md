# CONTEXTO MAESTRO — Integración VaN3Twin + SUMO-GEO 3D Web

> **Propósito de este documento**: retomar el proyecto en un chat nuevo sin perder estado.
> Describe cada componente, sus ficheros clave, cómo funciona, sus gotchas y **cómo
> modificarlo y verificarlo**. Los detalles finos viven en los contextos específicos:
> `CONTEXTO_SUMO_GEO.md`, `CONTEXTO_VAN3TWIN.md`, `CONTEXTO_CAPTURAS_WEB.md` (misma carpeta).
> Última actualización: 2026-08-29. Autor del proyecto: Pablo Barbecho (UCuenca).

---

## 0. Visión general

Gemelo digital vehicular para docencia: **VaN3Twin** (ns-3 + ETSI ITS-G5, corre SUMO
internamente por TraCI) sincronizado en *lockstep* con un **visor 3D web** (SUMO-GEO:
FastAPI + MapLibre/deck.gl) como segundo cliente TraCI de solo lectura. Además, un
**modo Replay offline** reproduce corridas grabadas (.pcap + signal-rx.csv) mostrando
mensajes CAM/CPM/DENM con contenido ASN.1, RSSI y estadísticas PHY.

```
┌──────────────── contenedor van3twin ────────────────┐
│ ns-3 (EVA 802.11p) ──lanza──> SUMO --num-clients 2  │
│   cliente TraCI #1 (setOrder 1)      puerto 3400+   │
└─────────────────────────────────────────────────────┘
          ▲ volumen van3twin_ns3-workspace (RO)
┌─ backend (FastAPI :8000) ─┐   ┌─ frontend (nginx :8081) ─┐
│ cliente TraCI #2 (order 2)│──▶│ MapLibre + deck.gl       │
│ WS /ws/live (+?replay=1)  │   │ interpolación + replay   │
└───────────────────────────┘   └──────────────────────────┘
```

### Repos GitHub (respaldo y réplica — todo en main/master)
| Repo | Contenido | Rama |
|---|---|---|
| `Pbarbecho/SUMO_GEO` | visor web (backend+frontend) | main |
| `Pbarbecho/VaN3TwinGEO` | fork de DriveX-devs/VaN3Twin con los 8 parches | master |
| `Pbarbecho/van3twin-docker` | Dockerfile, compose, docs, prácticas | main |

Rutas locales del Mac de Pablo:
- `~/van3twin-docker` — stack Docker + carpeta de docs `Intergracion SUMO 3D WEB VAN3TWIN/`
- `~/Dropbox/Mac/Documents/SUMO_GEO` — repo del visor (la ruta se inyecta al compose vía `.env` local: `SUMO_GEO_DIR=...`; los estudiantes clonan lado a lado y usan el default `../SUMO_GEO`)
- El árbol ns-3 **NO** vive en el Mac: vive en el **volumen Docker** `van3twin_ns3-workspace` (ver §1).

---

## 1. Componente: VaN3Twin / ns-3 (contenedor `van3twin`)

**Qué es**: fork de VaN3Twin (ns-3-dev con módulos automotive/traci/gn+btp). Ejemplo de
trabajo: `v2v-emergencyVehicleAlert-80211p` ("EVA"). Imagen `van3twin:jammy` (arm64).

**Dónde vive el código**: volumen nombrado `van3twin_ns3-workspace` montado en
`/home/vanet/VaN3Twin`. **Nunca** bind-mount al Mac: APFS (y NTFS) son case-insensitive
y el repo tiene pares que colisionan (`BOOLEAN.h/boolean.h`, `INTEGER.h/integer.h`,
`ActionID/ActionId`, `IVILaneWidth/IviLaneWidth`) → la compilación se rompe.
Se edita dentro del contenedor (`docker compose exec van3twin bash` o VS Code Dev Containers).

**Los 8 ficheros parcheados** (respaldados en el fork `VaN3TwinGEO`, rama master):
1. `src/traci/model/traci-client.cc` — `NS_OBJECT_ENSURE_REGISTERED(TraciClient)`;
   tras conectar, si `m_sumoAddCmdOpt` contiene `--num-clients` → `setOrder(1)`.
2. `src/automotive/examples/v2v-emergencyVehicleAlert-80211p.cc` — flag nuevo
   `--num-traci-clients=N` (agrega `" --num-clients N"` a las opciones de SUMO).
   OJO: el EVA fija `SumoPort=3400` (no el default 1338) y pisa atributos por
   `SetAttribute`, por eso el flag propio (los `--ns3::Clase::Attr` del CLI no sirven aquí).
3. `src/automotive/model/Applications/emergencyVehicleAlert.cc` — `logSignalCSV` (escribe
   `signal-rx.csv`: rx,tx,t_ms,rssi,snr) usando `addCARxCallbackExtended` /
   `addCPRxCallbackExtended` (SignalInfo: timestamp/rssi/snr/sinr/rsrp/size; conviven con
   los callbacks planos — caBasicService.cc:381). Gotchas C++: el campo ASN.1 es
   `stationId` (d minúscula); definir `logSignalCSV` ANTES de `StartApplication`;
   la lambda CPM necesita firma propia (`Seq<CollectivePerceptionMessage>`, `StationID_t`).
4-8. CMakeLists y ficheros de escenario asociados.

**Ejecución típica** (dentro del contenedor, `~/VaN3Twin/ns-3-dev`):
```bash
./ns3 run "v2v-emergencyVehicleAlert-80211p --num-traci-clients=2"
# ojo: ./ns3 run parte los args por espacios e ignora comillas internas → usar formas con '='
```
SUMO queda "waiting for 2 clients"; el visor (cliente 2) lo destraba.
`GetFreePort()` corre el puerto 3400→3401… si el anterior está en TIME_WAIT (~60 s
entre corridas) → el backend escanea 3400-3410.

**Cambios futuros aquí**: editar en el volumen → `./ns3 build` → probar → copiar el
fichero cambiado al fork y push (`git -C` sobre un clon del fork, o `docker cp` afuera).
El Dockerfile clona `VAN3TWIN_REPO` (build-arg, apunta al fork) en la imagen, así los
rebuilds ya salen parcheados.

**Salidas de una corrida**: `v2v-EVA-*.pcap` (DLT 105) + `signal-rx.csv` →
`cp v2v-EVA-*.pcap signal-rx.csv ~/results/` (bind `./results` del Mac = `/replay` del backend).

**Modelos de propagación** (para docencia): los ejemplos 802.11p usan
`YansWifiChannelHelper::Default` = LogDistance (n=3.0, RefLoss 46.6777 dB@1m) +
ConstantSpeed. Alternativas en el código: CniUrbanmicrocell (comentada), LTE/C-V2X:
cv2x_CniUrbanmicrocell, NR-V2X: 3GPP V2V_Highway, Sionna: ray tracing.

---

## 2. Componente: SUMO-GEO backend (FastAPI, servicio `backend`)

**Repo**: `SUMO_GEO/backend/`. Imagen propia `Dockerfile.van3twin` +
`requirements-van3twin.txt` (traci/sumolib **1.12.0** — debe coincidir con el SUMO del
contenedor van3twin; el `requirements.txt` normal pina 1.27.1 para el modo managed).

**Ficheros clave** (`backend/app/`):
- `config.py` — Settings prefijo `APP_`. Importantes: `sumo_mode` (managed|remote),
  `sumo_host/port`, `sumo_port_scan` (escaneo 3400-3410), `sumo_order` (2),
  `net_file`, `poly_file`, `step_length` (0.5), `max_fps`, `replay_dir=/replay`,
  `replay_pattern`, `asn_dir=/ns3/ns-3-dev/src/automotive/model/ASN1`.
- `sumo_bridge.py` — modo remote: bucle de puertos con `client.init(..., numRetries=1)` +
  `setOrder`; `step()` pide objetivo absoluto `simulationStep(getTime()+step_length)`
  (así el visor NO frena a ns-3).
- `geo.py` — detección de georreferencia con `convertXY2LonLat(0,0)` (sumolib 1.12 no
  tiene `hasGeoProj()`; el bug dibujaba Turín sobre Cuenca).
- `replay.py` — **todo el modo replay** (ver §4).
- `main.py` — `lifespan` (necesita net+poly para no caer al .sumocfg → `APP_POLY_FILE=/no_poly.xml`),
  WS `/ws/live` (rama `?replay=1` → `_ws_replay`), REST `/api/replay/info` (incluye `phy`),
  `_get_replay()` con huella (mtime/size de pcaps+signal*.csv) → **recarga sola** al copiar
  una corrida nueva, sin restart.

**Cambios futuros aquí**: editar en el Mac → `cd ~/van3twin-docker &&`
`docker compose --profile visor build backend && docker compose --profile visor up -d`
(**nunca** `docker compose build` a secas: reconstruye también la imagen grande de van3twin).
Verificar: `curl localhost:8000/api/replay/info | python3 -m json.tool`.

**Puntos de atención**: cada WS crea un SumoBridge (recargar la página en modo remote
mata al cliente TraCI 2 → "un visor por corrida"); selector Bajo/Medio/Alto solo managed;
una sola conexión remote por proceso (traci global sin labels).

---

## 3. Componente: SUMO-GEO frontend (nginx :8081)

**Repo**: `SUMO_GEO/frontend/` — estático puro (index.html, style.css, app.js,
nginx.conf, ucuenca.png), servido por nginx con **`Cache-Control: no-store`**
(cambios visibles con recargar; ante dudas `Cmd+Shift+R`). Es bind mount: editar y recargar,
sin rebuild.

**app.js — arquitectura**:
- **Interpolación**: estado `frameVehicles/interpPrev/interpT0/interpPeriod`, `angleLerp`
  (arco corto), `INTERP_MAX_JUMP=80m`, `INTERP_MAX_VEH=1500`, ritmo adaptativo
  `interpMinInterval(n)`. **Bug histórico clave**: el handler de frame NO debe asignar
  `vehicles = msg.vehicles` cuando interpola (salto+retroceso).
- **Capas deck.gl**: solo se reconstruyen por tick las dinámicas
  `DYN_IDS = {vehicles, veh-selected, v2x-pulse, v2x-arc, v2x-arc-lbl}`
  (`refreshDynamicLayers`, `makeVehiclesLayer`, `makeHighlightLayer`, `makeMessageLayers`).
- **Replay UI**: `replayMode/paused` (congela mensajes con `frozen`), `selStation`
  (filtro emisor + anillo ámbar), `showArcLabels` ("N m · X dBm"), seek/step/step_back/play,
  clic en pulso o arco → `inspect` (con hint `mtype`) → popup `interactive` con capas
  `<details>` estilo Wireshark. `msg_detail` usa clave **`mtype`** (no `type`).
- **Paneles**: auto-colapso con pin 📌 (localStorage `pin-<id>`); botón zen ⛶
  (`body.zen` oculta todo); panel PHY con `loadPhyStats()`.

**Tema institucional UCuenca (29-ago)**: paleta en `:root` de style.css —
`--ucu-azul:#002856`, `--ucu-rojo:#A51008`, `--panel:#002856e6`, `--bg:#001229`,
`--btn:#0d3a72`, `--btn-hover:#14508f`, `--line:#1c4370`, `--accent:#6db1ff`.
Filete rojo `border-top:3px solid var(--ucu-rojo)` en los 4 paneles. Logo
`ucuenca.png` (emblema "U", del sitio oficial) con `.uc-logo` = **badge blanco circular**
(el emblema es azul y se perdería sobre el panel azul) + subtítulo `.uc-sub`
"UNIVERSIDAD DE CUENCA". Alternativa vectorial: `Nova.svg` oficial (4 rects azul/rojo,
`ucuenca.edu.ec/wp-content/themes/uc-core-theme/dist/assets/svg/Nova.svg`).

**Cambios futuros aquí**: editar → recargar navegador. Para cambiar la paleta tocar solo
los tokens de `:root`. Colores aún hardcodeados a revisar si se re-tematiza de nuevo:
colores CAM/CPM/DENM en index.html (`#4da3ff/#37c871/#ff5347`), rampa LOS, anillo ámbar
`[255,210,63]` en app.js.

---

## 4. Componente: Replay offline V2X (`backend/app/replay.py`)

**Entrada**: `~/results/` del Mac = `/replay` (RO) — `v2v-*.pcap` + `signal*.csv` opcional.

**Parser pcap**: DLT 105 (802.11 sin radiotap) → LLC/SNAP ethertype 0x8947 →
GeoNetworking: Basic(4) + Common(8) + SO PV(24: GN_ADDR 8, TST 4, lat 4, lon 4,
PAI+speed 2, heading 2) + reserved(4) → BTP-B en gn[40] (puertos 2001 CAM /
2002 DENM / 2009 CPM), payload en gn[44]. Movilidad de los emisores desde el SO PV.
MAC ns-3 = `00:00:00:00:00:(node+1)`. El **pool de nodos se reutiliza** entre vehículos
SUMO → mapeo nodo→stationID por **segmentos temporales** decodificando los CAM propios.

**Decode ASN.1** (lazy, asn1tools, specs del volumen `APP_ASN_DIR`):
CAM = `asn1-v2/EN302637-2v141-CAM.asn` + CDD; **CPM = `full-v1-v2/CPM-all.asn`**
(top `CollectivePerceptionMessage`, compila 0.3 s — la variante TR103562+ISO19091 tarda
minutos, no usar). Decode en `asyncio.to_thread`. El t de un arco es de RECEPCIÓN
(hasta ~16 ms tras el TX por cola/backoff) → tolerancia ±20 ms con hint de tipo;
ventana de receptores 30 ms.

**signal-rx.csv**: `_load_signal()` — cabeceras flexibles, heurística ms/s, asocia
(tx,rx) ±50 ms → RSSI en eventos, `receivers_info` (dist+rssi) en decode, bloque en PHY.

**phy_stats()** (cacheada): latencia TX→RX (pares estación/tipo/±30 ms), cobertura
(trayectorias `_pos_at`), PER (esperadas por coexistencia), PDR clampado ≤1.0,
utilización de canal por airtime, config del EVA (10 MHz, **12 Mbit/s = 16-QAM 1/2**).
Sin potencia TX (pcap sin radiotap — documentado). Referencia corrida de prueba:
lat p50 0.14 ms/máx 27 ms, cobertura p95 183 m/máx 311 m, PER 13.7 %, canal ~0.7 %.
RSSI real validado: 6 m→-45.8 dBm … 135 m→-81.7 dBm ⇒ n≈2.66 (modelo LogDistance n=3.0).

**Protocolo WS** (`_ws_replay`): cmds `pause/play/speed/seek/step/step_back/inspect`;
`step_back` = `t = max(t0, t-2*step)` + un frame single.

**Cambios futuros aquí**: igual que backend (§2). Testeable sin Docker: el módulo corre
standalone en sandbox contra pcaps copiados (así se validó: 8 861 TX / 47 852 RX).

---

## 5. Componente: stack Docker (`~/van3twin-docker/docker-compose.yml`)

Proyecto `van3twin`, **un solo compose** con profile:
- `docker compose up -d` → solo van3twin (ns-3 + Xvfb/fluxbox/x11vnc automáticos).
- `docker compose --profile visor up -d` → + backend (:8000) + frontend (:8081).

Puertos: 8080 vehicle-visualizer, 5901→5900 VNC (`vnc://127.0.0.1:5901`), 8090 http.server,
8000 backend, 8081 frontend. Volúmenes: `ns3-workspace` (RW van3twin, RO backend en `/ns3`),
`./results` (RW van3twin en `~/results`, RO backend en `/replay`).
Env backend: modo remote, host van3twin, puerto 3400 + scan 10, order 2, net del EVA,
poly inexistente, step 0.5, replay pattern.
Parametrización para estudiantes: `${SUMO_GEO_DIR:-../SUMO_GEO}` y build-args
`VAN3TWIN_REPO` (fork) / `VAN3TWIN_REF` (master).

**Regla de oro de builds**: `--profile visor build backend` y luego `up -d`.
`docker compose build` a secas reconstruye van3twin (1-3 h). Cancelar un build es seguro.

**Cambios futuros aquí**: editar compose → `docker compose --profile visor up -d`
(recrea solo lo cambiado). `down -v` borra el volumen ns-3 (¡solo si se quiere reset total!).

---

## 6. Componente: documentación y prácticas (carpeta `Intergracion SUMO 3D WEB VAN3TWIN/`)

Estilo LaTeX institucional: azul #002856 / rojo #A51008, compilar con `pdflatex` (2 pasadas).
Unicode: sin ⚠✓⏮⏭ directos (usar amssymb / \checkmark).

| Documento | Contenido |
|---|---|
| `MANUAL_SIMULACION_VAN3TWIN_SUMO_GEO.md` + `.tex/pdf` | manual operativo: modos con diagramas, pasos A-B-C, replay, depuración, cuándo `--build`, resumen de comandos |
| `Practica_Replay_V2X.tex/pdf` | práctica: teoría ETSI CAM/DENM/CPM, ASN.1/UPER, RSSI/log-distancia con cálculos reales, sensibilidades 802.11p, modelos de canal; replay web vs Wireshark; 9 ejercicios; capturas reales en `img/` |
| `Practica_Instalacion_Framework.tex/pdf` | práctica de instalación: teoría git/docker (con docker vs compose, sensibilidad al directorio, qué es cada fichero), trabajo previo, Linux→Windows(WSL2)→macOS, verificación por niveles 0-5 |
| `CONTEXTO_SUMO_GEO.md` / `CONTEXTO_VAN3TWIN.md` | estado técnico detallado por componente (mantener al día) |
| `CONTEXTO_MEJORAS_VISOR_V2X.md` | resumen de las mejoras del visor (29-ago: cockpit, sensores, detección HUD, replay mejorado, V2X en vivo) — insumo ya usado para la práctica nueva |
| `Practica_Visor_V2X_Tiempo_Real.tex/pdf` | práctica nueva (8 págs, 29-ago): V2X en vivo, cockpit, HUD detección, sensores, replay mejorado; marco teórico de los 3 relojes/jitter/cadena en vivo/patrones MIT; 6 casos de depuración como material didáctico; 7 ejercicios. Prerrequisitos: instalación + replay. SIN capturas aún (el modo vivo no es reproducible en sandbox — capturar en el Mac) |
| `CONTEXTO_CAPTURAS_WEB.md` + `tools/captura_web.py` | pipeline de capturas PNG (ver §7) |
| `RESPALDO.md` | plan de respaldo GitHub ejecutado |

**Cambios futuros aquí**: editar .tex → `pdflatex` ×2 → actualizar el contexto correspondiente.
Tras cualquier cambio de código: actualizar también el CONTEXTO_* afectado (costumbre del proyecto).

---

## 7. Componente: pipeline de capturas (sandbox + Playwright)

Para ilustrar prácticas: stack completo en el sandbox Linux (uvicorn con backend+frontend
combinados, mismo puerto) + Chromium headless. Trucos imprescindibles (detalle en
`CONTEXTO_CAPTURAS_WEB.md`): (1) `playwright install chromium` sin `--with-deps` +
extraer `libxdamage1` con `apt-get download`+`dpkg -x`+`LD_LIBRARY_PATH` (aarch64);
(2) `--no-sandbox`; WebGL va por SwiftShader; unpkg y tiles.openfreemap.org accesibles;
(3) **pausar inmediatamente tras seek** (si no, el server reproduce hasta el final);
(4) expandir paneles con `style.maxHeight='none'`; (5) todo en UNA llamada bash
(los procesos de fondo y /tmp mueren entre llamadas).

---

## 8. Estado actual y pendientes (29-ago-2026)

**Hecho y validado**: integración lockstep end-to-end; interpolación fluida; replay
completo (timeline, step/step_back, filtro por vehículo, popup ASN.1 por capas, RSSI+
distancia en arcos, panel PHY, recarga automática); compose unificado con profile;
manual + 2 prácticas en PDF con capturas reales; respaldo en 3 repos GitHub;
**tema UCuenca aplicado al visor** (verificado con captura).

**Pendiente**:
- [ ] `git push` de los últimos cambios en SUMO_GEO (tema+logo, mejoras visor) y van3twin-docker (contextos, prácticas — incluida la nueva `Practica_Visor_V2X_Tiempo_Real`) — comandos ya entregados a Pablo.
- [ ] Capturas para `Practica_Visor_V2X_Tiempo_Real` (en el Mac, con corrida en vivo; los modos sensor dan buenas figuras) e insertarlas en el .tex.
- [ ] Opcional: imagen Docker Hub (descartada para clases; queda la práctica de instalación).
- [ ] Posibles siguientes pasos hablados: nada comprometido; el proyecto está en punto estable.

**Convenciones al continuar en otro chat**:
1. Leer este documento + el CONTEXTO_* del componente a tocar.
2. Frontend: editar y recargar. Backend: two-step build (§2). ns-3: dentro del volumen (§1).
3. Actualizar el CONTEXTO_* correspondiente tras cada cambio y recordar el push a GitHub.
