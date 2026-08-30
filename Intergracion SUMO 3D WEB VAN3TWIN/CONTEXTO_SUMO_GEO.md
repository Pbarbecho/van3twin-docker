# Contexto del proyecto SUMO_GEO (GEO SUMO WEB)

> Contexto de trabajo para la migración/integración con VaN3Twin.
> Complementa `GUIA_INTEGRACION_SUMO_GEO.md` y `CONTEXTO_VAN3TWIN.md`.
> Código local: `/Users/Pablo_1/Dropbox/Mac/Documents/SUMO_GEO` · Repo: https://github.com/Pbarbecho/SUMO_GEO

## Qué es

Aplicación web para **ejecutar y visualizar simulaciones SUMO en el navegador**: edificios 3D, vehículos 3D procedurales (LOD automático), semáforos sincronizados con SUMO, estimación de tráfico LOS (A–F) por calle, inspector de clic derecho y panel de históricos. Stack: **FastAPI (backend) + MapLibre GL JS + deck.gl (frontend, sin build step) + nginx**. Prototipo de investigación de la Universidad de Cuenca.

```
SUMO ──TraCI (suscripciones)──► backend FastAPI ──REST────► red + edificios + semáforos (GeoJSON, cacheado)
                                              └──WebSocket► vehículos + LOS + semáforos + stats por paso
                                                            └► nginx :8081 ► navegador (MapLibre + deck.gl)
```

## Estructura

| Ruta | Rol |
|---|---|
| `backend/app/config.py` | `Settings` (pydantic-settings, prefijo `APP_`, `.env`). |
| `backend/app/main.py` | FastAPI: REST + WS `/ws/live`. Un `SumoBridge` **por conexión WS**. |
| `backend/app/sumo_bridge.py` | Wrapper TraCI/libsumo: start/step/vehicles/stats/inspector/tls. |
| `backend/app/geo.py` | `NetworkGeo` (net→GeoJSON, xy→lonlat), `cfg_paths()`, edificios, semáforos. |
| `backend/app/traffic.py` | Densidad por edge → LOS HCM (A–F) + color. Solo edges activos (O(vehículos)). |
| `backend/Dockerfile` | python:3.11-slim + libs GL/X11 + `eclipse-sumo` (modo managed). |
| `backend/requirements.txt` | fastapi 0.115.6, uvicorn 0.34.0, websockets 14.1, **eclipse-sumo/traci/sumolib==1.27.1**, pyproj. |
| `frontend/app.js` (~980 líneas) | Toda la lógica del visor: capas deck.gl, LOS, semáforos, presets de luz, inspector, históricos. |
| `frontend/nginx.conf` | Proxy same-origin: `/api/` y `/ws/` → `backend:8000`; resto estático. |
| `docker-compose.yml` | Servicios `backend` (:8000) y `frontend` (nginx :8081). Monta `./sumo` y `./mapa` (RO). |
| `sumo/`, `mapa/` | Escenarios: `metro_{low,mid,high}` (toda Cuenca, 24 h), `cuenca*` (OSM con edificios), `demo`. |
| `scripts/` | `build_city.sh` (OSM→net+poly), `gen_traffic.py`, `enrich_heights.py`. |

## Configuración (`Settings`, prefijo `APP_`)

- `sumo_mode`: `managed` (backend lanza SUMO; default) | `remote` (conecta a TraCI ya corriendo).
- `sumo_binary`, `sumo_config` (`/sumo/demo.sumocfg`), `sumo_host` (`sumo`), `sumo_port` (**8813**), `use_libsumo`, `step_length` (1.0).
- `sumo_config_template` (`/mapa/metro_{level}.sumocfg`) + `sim_begin`: selector Bajo/Medio/Alto vía `?level=` del WS.
- `net_file`/`poly_file`: overrides opcionales; **si falta cualquiera de los dos, `lifespan` parsea el `.sumocfg`** (`cfg_paths`) — relevante para el truco `APP_POLY_FILE=/no_poly.xml` de la guía.
- `origin_lon/lat` (ancla ENU para redes sin proyección), `view_lon/lat` (centro inicial), `max_fps` (10), `cors_origins`.

## Flujo en runtime

**Arranque (lifespan)**: carga la red una vez (`NetworkGeo`), cachea GeoJSON de edges, edificios y semáforos, y `meta` (center/bounds/origin/step_length/mode).

**REST**: `/api/health`, `/api/meta`, `/api/network`, `/api/buildings`, `/api/trafficlights`.

**WS `/ws/live`**: acepta → crea `SumoBridge` → `bridge.start(config, begin)` → envía `{"type":"meta",...}` → bucle: `step()` → `vehicles()` → frame `{"type":"frame","t","vehicles","edges","tls","stats"}` → `sleep(1/fps)`. Fin de simulación (`getMinExpectedNumber()<=0`) → `{"type":"end"}`. Comandos del cliente: `pause`, `play`, `speed{fps}`, `inspect{id}` (responde `{"type":"inspect",...}`). Error en start → `{"type":"error"}` + close.

**`SumoBridge` claves**:
- Suscripciones TraCI `_SUB_VARS` (POSITION, ANGLE, SPEED, TYPE, ROAD_ID, CO2, WAITING): flota completa en 1 round-trip; fallback a polling.
- `start()` rama remote: `client.init(host, port)` — **hoy sin `setOrder`** (módulo `traci` global, sin label).
- `step()`: **hoy `simulationStep()` a secas** (un paso por frame).
- Cachea dimensiones por vType; agrega CO₂/espera/travel-time para el panel histórico.
- `close()` cierra la conexión TraCI al desconectarse el WS.

**Coordenadas** (`geo.py`): red con proyección real (OSM) → `net.convertXY2LonLat`; red sintética → aproximación ENU anclada en `origin_lon/lat`.

## Escenario activo en `docker-compose.yml`

Modo `managed`, escenario metro (`/mapa/metro_mid.sumocfg`, template `metro_{level}`), vista en el centro de Cuenca, `APP_SIM_BEGIN=28800` (08:00). Alternativa comentada: `cuenca*` OSM con edificios. Puertos: backend `8000:8000`, frontend `8081:80` (el comentario de cabecera dice 8080 — desactualizado, el puerto real es **8081**).

## Estado respecto a la migración VaN3Twin

**Pasos 2–4 APLICADOS (2026-08-25):**

1. ✅ `config.py`: `sumo_order: int = 0` (línea 39).
2. ✅ `sumo_bridge.py` `start()` remote: `client.setOrder(settings.sumo_order)` si `sumo_order>0`.
3. ✅ `sumo_bridge.py` `step()`: en remote+order, objetivo absoluto `simulationStep(getTime() + step_length)`.
4. ✅ Nuevos: `backend/requirements-van3twin.txt` (**traci/sumolib==1.12.0**, sin `eclipse-sumo`), `backend/Dockerfile.van3twin`, `docker-compose.van3twin.yml` (red `van3twin_default` y volumen `van3twin_ns3-workspace` externos; `APP_SUMO_HOST=van3twin`, `APP_SUMO_PORT=3400` — el EVA fija SumoPort=3400, no el default 1338 —, `APP_SUMO_ORDER=2`, net del EVA desde el volumen RO).

**INTEGRACIÓN VALIDADA Y FUNCIONANDO (25-ago-2026):** visor 3D sobre Turín en lockstep con VaN3Twin. Procedimiento operativo completo en `MANUAL_SIMULACION_VAN3TWIN_SUMO_GEO.md`.

Cambios finales adicionales en este repo (post-guía, todos verificados):

1. `config.py`: `sumo_order` y `sumo_port_scan` (nuevo: nº de puertos extra a probar).
2. `sumo_bridge.py` `start()` remote: bucle de conexión sobre `sumo_port..sumo_port+scan` con `numRetries=1` + `setOrder(order)`. Motivo: el `GetFreePort()` de ns-3 corre el puerto (3400→3401…) cuando el anterior queda en TIME_WAIT entre corridas.
3. `sumo_bridge.py` `step()`: objetivo absoluto `simulationStep(getTime()+step_length)` en remote+order.
4. `geo.py`: no usar `net.hasGeoProj()` — **no existe en sumolib ≤1.12** y el `except` lo dejaba en False, dibujando la red de Turín anclada en Cuenca (bug visto en vivo). Ahora se prueba `convertXY2LonLat(0,0)` directamente.
5. Nuevos: `backend/requirements-van3twin.txt`, `backend/Dockerfile.van3twin`.
6. **Interpolación de movimiento en el frontend (25-ago, noche):** `app.js` interpola posición/rumbo entre frames vía `requestAnimationFrame` (estado: `frameVehicles`/`interpPrev`/`interpT0`/`interpPeriod`; helpers `angleLerp`, `metersBetween`; tope `INTERP_MAX_VEH=1500`, anti-teleport `INTERP_MAX_JUMP=80 m`). Refinamientos posteriores: los ticks refrescan **solo la capa `vehicles`** (`makeVehiclesLayer` + `refreshVehiclesLayer`, capas restantes reutilizadas por identidad), ritmo adaptativo por tamaño de flota (`interpMinInterval`), y **bugfix clave**: el handler de frame NO asigna `vehicles = msg.vehicles` (pintar la posición nueva causaba salto+retroceso); solo fija `frameVehicles` como objetivo. `nginx.conf` sirve estáticos con `Cache-Control: no-store` (evita depurar contra app.js cacheado). `APP_STEP_LENGTH` default del modo van3twin bajó a **0.5**. Sin cambios en el backend.
7. **Replay offline de mensajes V2X (25-ago, noche):** nuevo `backend/app/replay.py` — parsea los `.pcap` de VaN3Twin (DLT 105, LLC/SNAP 0x8947, GN Basic(4)+Common(8)+SO PV(24)+res(4), BTP-B en gn[40], payload en gn[44]; puertos 2001 CAM/2002 DENM/2009 CPM), reconstruye movilidad desde el SO PV (lat/lon/speed/heading del emisor), eventos TX/RX, PDR por pares, y decodifica contenido ASN.1 **bajo demanda** con asn1tools + los `.asn` del árbol (CAM: `asn1-v2/EN302637-2v141-CAM.asn`+CDD; **CPM: `full-v1-v2/CPM-all.asn`, top `CollectivePerceptionMessage` — la variante TR103562+ISO19091 tarda minutos en compilar**). El pool de nodos ns-3 se REUTILIZA entre vehículos SUMO → mapeo nodo→stationID por segmentos temporales decodificando todos los CAM propios. WS: `?replay=1` en `/ws/live` (reproductor con seek; `_ws_replay` en main.py), REST `/api/replay/info`. Clave del tipo en `msg_detail` es `mtype` (un `"type"` en el `**det` pisaba el `"type":"msg_detail"` — bug histórico). Frontend: botón Replay, timeline, capas `v2x-pulse`/`v2x-arc` animadas en el tick de interpolación, clic en pulso → popup con contenido. Compose: `./results:/replay:ro` + `APP_REPLAY_PATTERN`. Extras (25-ago, madrugada): cmd WS `step` (un frame y re-pausa; flag `single` en `_ws_replay`), selector de vehículo emisor (`selStation`, `#veh-filter`, filtra por `e.st` en pulsos y arcos), y modo congelado — con `replayMode && paused` los mensajes no se desvanecen (prog fijo 0.35, sin prune) y los vehículos saltan al frame sin interpolar. Todo validado end-to-end en sandbox contra los pcaps reales del EVA (8.861 TX / 47.852 RX, carga 0.5 s; step: 1 frame exacto por comando). UI: los controles de replay viven en un **panel propio `#replay-panel` ("Replay V2X")** en la columna izquierda bajo el panel SUMO·GEO (`#left-col` flex; ambos con auto-colapso). Capturas PNG del visor para documentos: pipeline reproducible en `CONTEXTO_CAPTURAS_WEB.md` + `tools/captura_web.py` (stack completo en sandbox + Playwright headless; imágenes en `img/`). Documento didáctico aparte: `Practica_Replay_V2X.tex/pdf` (replay web vs Wireshark, con marco teórico ETSI CAM/DENM/CPM/ASN.1-UPER + tabla de unidades, tabla de contraste y ejercicios); el manual solo referencia. Refinamientos (26-ago): arcos clicables (decode tolerante ±20 ms con hint de tipo — el t del arco es de RECEPCIÓN, hasta ~16 ms tras el TX por cola/backoff; ventana de receptores 30 ms), popup con clase `interactive` (el `#popup` base lleva `pointer-events:none` — por eso no se podía hacer scroll; la clase lo habilita + botón ✕), y cmd `step_back` (t = t−2·step y un frame) con botones icon-only ⏮/⏭. Refinamientos (26-ago, 2ª tanda): `decode()` devuelve `layers` (802.11/GeoNetworking-SO PV/BTP; `_payloads` guarda `(payload, meta)` — ojo al desempaquetar) y el popup los muestra como `<details>` plegables estilo Wireshark; pin 📌 en los paneles (`.pin` inyectado por JS en el h1, estado en localStorage `pin-<id>`, bloquea el auto-colapso). **Panel PHY 802.11p** (26-ago, 3ª tanda): `replay.py.phy_stats()` (cacheada) mide latencia TX→RX (emparejando rx→tx por estación/tipo/±30 ms), rango de cobertura (distancia emisor-receptor vía trayectorias `_pos_at`), PER global (esperadas = coexistencia por vida de trayectoria), PDR clampado a 1.0 (bordes de reutilización del pool duplican alguna RX), tasas y utilización de canal por airtime (~40 µs + bytes/12 Mbps); config PHY del EVA como constantes; SIN potencia RX (pcap sin radiotap — documentado). Expuesta en `/api/replay/info` clave `phy`; frontend `#phy-panel` + `loadPhyStats()` (fetch al entrar en replay). **Recarga automática del índice (26-ago):** `_get_replay()` compara una huella (path, mtime, size) de pcaps+signal*.csv del replay_dir y recarga si cambió — ya NO hace falta `restart backend` al copiar una corrida nueva a `~/results` (validado: 2ª consulta detectó el CSV nuevo sin reinicio). Valores de referencia de la corrida de prueba: lat p50 0,14 ms/máx 27 ms, cobertura p95 183 m/máx 311 m, PER 13,7 %, canal ~0,7 %. **RSSI + distancia en enlaces (26-ago, 4ª tanda):** `_load_signal()` ingiere `signal*.csv` opcional del replay_dir (formato `rx,tx,t_ms,rssi[,snr]`; cabeceras flexibles; heurística ms/s; asocia por (tx,rx) ±50 ms) → `e["rssi"]` en eventos RX, `receivers_info` (dist vía `_pos_at` + rssi) en `decode()`, bloque `rssi_dbm` y nota dinámica en `phy_stats()`. Frontend: TextLayer `v2x-arc-lbl` con "N m · X dBm" en el punto medio del arco (visible si frozen o ≤40 arcos), popup con receptores (dist, rssi), fila RSSI en panel PHY. Generación del CSV: parche al EVA con `addCARxCallbackExtended`/`addCPRxCallbackExtended` (SignalInfo: timestamp/rssi/snr/sinr/rsrp/size; ambos callbacks conviven — verificado en caBasicService.cc:381) — código en la práctica. **Corrección PHY (26-ago):** a 10 MHz, 12 Mbit/s = **16-QAM 1/2** (no QPSK 1/2 — eso es 6 Mbit/s en ese BW); corregido en `phy_stats()` config y en la práctica, que ahora incluye teoría RSSI/log-distancia con cálculos y la tabla de sensibilidades IEEE por tasa. **Gotchas del parche C++ (vistos al compilar):** el campo del header ASN.1 es `stationId` (d minúscula, no `stationID` como en el decode Python); `logSignalCSV` debe definirse ANTES de `StartApplication`; la lambda del CPM necesita su firma propia (`Seq<CollectivePerceptionMessage>`, `StationID_t`) — no reutilizar la del CAM. Validado end-to-end con CSV sintético (28.595 muestras asociadas). Al seleccionar un vehX en el filtro, el vehículo se **resalta con anillo ámbar** en el mapa (capa `veh-selected` en `makeHighlightLayer()`, incluida en refresh completo y dinámico).
8. **Compose unificado (25-ago, tarde):** los servicios `backend`/`frontend` del modo van3twin viven ahora en `~/van3twin-docker/docker-compose.yml` bajo el **profile `visor`** (`docker compose --profile visor up -d`; build context absoluto al repo SUMO_GEO; volumen `ns3-workspace` interno, sin red/volumen externos). `SUMO_GEO/docker-compose.van3twin.yml` fue **eliminado** (25-ago). Env: `APP_SUMO_PORT=3400`, `APP_SUMO_PORT_SCAN=10`, `APP_SUMO_ORDER=2`.

**Puntos de atención detectados en el código**:
- Cada conexión WS crea un `SumoBridge` nuevo y `close()` al desconectar → en remote, recargar la página cierra la conexión TraCI del cliente 2 (con `--num-clients 2` el run puede quedar inutilizable; "un visor por corrida", según la guía).
- El selector Bajo/Medio/Alto solo aplica en managed (busca `metro_{level}.sumocfg`); en modo van3twin no debe usarse.
- La rama remote ignora `config`/`begin`; usa el módulo `traci` global (sin labels) → una sola conexión remote por proceso.
- `lifespan` necesita `net_file` **y** `poly_file` para no caer al parseo del `.sumocfg` (de ahí `APP_POLY_FILE=/no_poly.xml`). Mejora opcional: tolerar `APP_POLY_FILE=""`.
- `requirements.txt` pina 1.27.1; el contenedor van3twin lleva SUMO **1.12.0** → los pines deben coincidir con el SUMO al que se conecta.
