# Manual: simulación conjunta VaN3Twin + SUMO-GEO (visor 3D web)

**Validado el 25-ago-2026.** Este manual describe cómo ejecutar una simulación V2X de
VaN3Twin (ns-3, ejemplo EVA 802.11p) visualizada en tiempo real y en 3D por SUMO-GEO
(MapLibre/deck.gl) sobre el mapa real de Turín, con ambos frameworks acoplados a la
**misma** instancia de SUMO mediante TraCI multi-cliente.

```
┌────────── contenedor van3twin ──────────┐    red docker      ┌──── stack SUMO-GEO ────┐
│ ns-3 (EVA) ─TraCI #1 (setOrder 1)─ SUMO │◄─ van3twin_default │ backend FastAPI :8000  │
│        --num-clients 2, puerto 3400+    │    TraCI #2 (RO)   │ (remote, setOrder 2)   │
└─────────────────────────────────────────┘                    │ nginx :8081 ◄─ browser │
                                                               └────────────────────────┘
```

SUMO avanza en *lockstep*: exige que ambos clientes pidan paso. ns-3 marca el ritmo con
pasos finos; el visor pide objetivos gruesos (t+1 s) y no lo frena.

---

## 1. Componentes y ubicaciones

| Pieza | Dónde | Rol |
|---|---|---|
| Stack van3twin | `~/van3twin-docker` (compose + Dockerfile) | Contenedor `van3twin` con ns-3/VaN3Twin y SUMO 1.12.0 |
| Árbol ns-3 compilable | volumen Docker `van3twin_ns3-workspace` | Único lugar donde se compila (case-sensitive) |
| Edición de código ns-3 | dentro del contenedor (`docker compose exec` o VS Code Dev Containers) | Se edita directamente en el volumen |
| Repo SUMO-GEO | `~/Dropbox/Mac/Documents/SUMO_GEO` | Backend FastAPI + frontend MapLibre/deck.gl |
| Servicios del visor | profile `visor` del mismo `~/van3twin-docker/docker-compose.yml` | backend (remote) + frontend nginx; solo arrancan con `--profile visor` |

Puertos en el Mac: **8081** visor SUMO-GEO · **8000** API backend · **8080** vehicle-visualizer
nativo de VaN3Twin · **5901** VNC (GUI de SUMO) · **8090** GEO SUMO WEB de la práctica.
El puerto TraCI (3400+) no se publica: viaja por la red Docker interna.

## 2. Requisitos previos (ya aplicados; verificar solo si algo falla)

El acoplamiento requiere estos parches, ya presentes y compilados:

1. **`traci-client.cc`** (ns-3): `NS_OBJECT_ENSURE_REGISTERED(TraciClient)` y llamada a
   `setOrder(1)` tras el connect cuando las opciones de SUMO contienen `--num-clients`.
2. **Ejemplo EVA** (`v2v-emergencyVehicleAlert-80211p.cc`): flag `--num-traci-clients=N`
   que añade `--num-clients N` al comando de SUMO.
3. **Backend SUMO-GEO**: `sumo_order`/`sumo_port_scan` en config, `setOrder(2)` + escaneo
   de puertos 3400–3410 al conectar, paso con objetivo absoluto, y detección de proyección
   compatible con sumolib 1.12 (`geo.py`).
4. **Servicios `backend`/`frontend`** (profile `visor` del compose de van3twin):
   `APP_SUMO_HOST=van3twin`, `APP_SUMO_PORT=3400`, `APP_SUMO_PORT_SCAN=10`,
   `APP_SUMO_ORDER=2`, net del EVA leído del volumen en RO.

Comprobación rápida de que los parches siguen en el volumen:

```bash
docker compose exec van3twin grep -c "num-clients" src/traci/model/traci-client.cc   # ≥ 1
```

## 3. Modos de ejecución y arranque

Todo vive en un solo compose (`~/van3twin-docker/docker-compose.yml`). Dos cosas
independientes definen el modo de operación: el **profile** decide qué contenedores
existen, y el flag **`--num-traci-clients`** decide, por corrida, si SUMO espera al
visor. Van siempre en pareja:

```
                      ¿Necesitas el visor 3D web?
                         │                  │
                      NO ▼                  ▼ SÍ
  ┌──────────────────────────────┐  ┌────────────────────────────────────────┐
  │ MODO A · VaN3Twin solo       │  │ MODO B · VaN3Twin + SUMO-GEO           │
  │                              │  │                                        │
  │ docker compose up -d         │  │ docker compose --profile visor up -d   │
  │ ./ns3 run "EVA ..."          │  │ ./ns3 run "EVA ...                     │
  │        (sin flag)            │  │        --num-traci-clients=2"          │
  │                              │  │                                        │
  │ SUMO arranca de inmediato    │  │ SUMO espera → abrir localhost:8081     │
  │ (1 cliente TraCI: ns-3)      │  │ → lockstep con el visor (cliente 2)    │
  └──────────────────────────────┘  └────────────────────────────────────────┘
```

> **Importante:** no levantar a la vez el `docker-compose.yml` normal del repo
> SUMO_GEO (modo *managed*, para uso autónomo del visor): comparte los puertos
> 8000/8081 con el Modo B y provocaría conflictos.

### Modo A — VaN3Twin solo (uso clásico)

```
  ┌── contenedor van3twin ────────────┐    backend y frontend del visor
  │  ns-3 ──TraCI #1 (único)──► SUMO  │    NO existen (profile apagado)
  └───────────────────────────────────┘
     vistas: sumo-gui por VNC :5901  ·  vehicle-visualizer 2D :8080
```

```bash
cd ~/van3twin-docker && docker compose up -d      # sin --profile: el visor no arranca
docker compose exec van3twin bash
./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true"
```

**Sin** `--num-traci-clients`: SUMO no espera a nadie y la simulación arranca de
inmediato. Opcionales: GUI de SUMO por VNC (`open vnc://127.0.0.1:5901` en el Mac y
quitar `--sumo-gui=false`) o el visor 2D nativo (`--vehicle-visualizer=true` → `:8080`).

### Modo B — VaN3Twin + visor 3D SUMO-GEO (profile `visor`)

```
  ┌── contenedor van3twin ───────────┐   red docker   ┌─ visor (profile) ─────┐
  │ ns-3 ──TraCI #1──► SUMO          │◄───────────────│ backend :8000         │
  │        --num-clients 2, :3400+   │  TraCI #2 (RO) │   ▲ nginx :8081       │
  └──────────────────────────────────┘                │   └── navegador       │
                                                      └───────────────────────┘
```

```bash
cd ~/van3twin-docker && docker compose --profile visor up -d
```

y seguir el §4 (Pasos A-B-C) lanzando el EVA **con** `--num-traci-clients=2`. Flag y
visor van siempre juntos: con el flag SUMO espera al visor; sin el flag, el visor no
puede conectar (pantalla en negro).

Se puede alternar entre modos sin tocar contenedores: si el visor ya está arriba pero
lanzas sin el flag, la simulación corre sola (Modo A) y el visor simplemente no conecta
en esa corrida.

### Mantenimiento del stack

Si cambió algo de `backend/` del repo SUMO_GEO (código Python, requirements,
Dockerfile): `docker compose --profile visor build backend && docker compose --profile visor up -d`. Uso diario → nada.

## 4. Ejecutar una simulación con el visor (el orden importa)

**Paso A — limpiar restos de la corrida anterior** (dentro del contenedor):

```bash
cd ~/van3twin-docker && docker compose exec van3twin bash
pkill -f ns3-dev-v2v; pkill sumo; sleep 1     # inofensivo si no hay nada
```

**Paso B — lanzar el EVA pidiendo 2 clientes TraCI:**

```bash
./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true --num-traci-clients=2"
```

Salida esperada: `Starting server on port 34XX`, `waiting for 2 clients...`,
`client connected` (ns-3) — y ahí **se queda esperando**. Es el comportamiento correcto:
SUMO no arranca hasta que conecte el visor. El puerto puede ser 3400, 3401, 3402…
(ns-3 salta al siguiente libre si el anterior quedó en TIME_WAIT ≈60 s); el backend
escanea 3400–3410 y lo encuentra solo.

**Paso C — abrir (o recargar) el visor:** `http://localhost:8081` en el navegador.
Al conectar el WebSocket verás en el Terminal el segundo `client connected` y
`Simulation version 1.12.0 started`: todo corre en lockstep. El visor abre sobre Turín
con los 7–8 vehículos del EVA.

**Reglas de la sesión:**

- **Un visor por corrida.** No recargues la página a mitad de simulación ni abras una
  segunda pestaña: SUMO fijó 2 clientes al arrancar. Si recargas, vuelve al Paso A.
- No uses el selector Bajo/Medio/Alto del visor (es del modo managed).
- Al terminar (`--sim-time` o fin de rutas), VaN3Twin cierra SUMO (`--quit-on-end`) y el
  visor pierde la conexión: es lo esperado. ns-3 imprime el resumen (CAMs, PRR, etc.).
- Nueva corrida = Paso A → B → C (el stack SUMO-GEO sigue arriba, no se toca).

## 5. Flags útiles del ejemplo EVA

| Flag | Efecto |
|---|---|
| `--num-traci-clients=2` | **Obligatorio para el visor**: SUMO espera 2 clientes TraCI |
| `--sim-time=250` | Duración de la simulación (s) |
| `--csv-log=nombre` | Log CSV por vehículo de la aplicación EVA |
| `--sumo-updates=0.1` | Sincronización TraCI cada 0.1 s sim (default 0.01) → ~10× menos overhead, acelera el lockstep |
| `--met-sup=true` | Metric supervisor (PRR, latencia) |
| `--vehicle-visualizer=true` | Visor 2D nativo además del 3D (`http://localhost:8080`) |
| `--send-cam=false` | Desactiva la transmisión de CAMs (escenario de referencia) |
| `--penetrationRate=0.5` | Fracción de vehículos con equipo V2X |

Sin espacios dentro de cada flag: el `./ns3 run` de este fork parte la cadena por
espacios sin respetar comillas internas.

## 5b. Velocidad de la simulación en el visor

El slider **Velocidad (fps)** de la web sí actúa: cada movimiento envía `{cmd:"speed"}`
al backend, que pide a SUMO un avance de `APP_STEP_LENGTH` (1 s simulado) por frame.
El techo del visor es por tanto `fps × 1 s` (10 fps → hasta 10× tiempo real; 30 fps →
30×). Pero en lockstep manda el cliente más lento, y suele ser **ns-3**: el EVA
sincroniza TraCI cada `sumo_updates = 0.01` s simulados por defecto.

Para acelerar, en este orden:

1. `--sumo-updates=0.1` en el comando del EVA (mayor impacto: ~10× menos
   sincronizaciones TraCI; posiciones cada 0.1 s sim, de sobra para el visor).
2. Subir el slider a 20–30 fps.
3. `APP_STEP_LENGTH` mayor (2–5) en el compose — más rápido pero movimiento a saltos.
4. Quitar carga a ns-3 si no se necesita: `--met-sup=false`, sin `--csv-log`.

**Fluidez (25-ago):** el frontend **interpola el movimiento entre frames** (posición y
rumbo, con detección de teletransportes) y el default pasó a `APP_STEP_LENGTH=0.5`. La
interpolación refresca **solo la capa de vehículos** y adapta su ritmo a la flota
(60 fps hasta 150 vehículos → ~11 fps hasta 1500; por encima se desactiva).

**Con flotas grandes hay dos límites distintos:**

1. *Render (frontend)*: resuelto con lo anterior.
2. ***ns-3 (VaN3Twin)***: el coste por segundo simulado crece con el nº de nodos
   (CAM/CPM broadcast ≈ O(N²) recepciones) y **ns-3 es mono-hilo** — más CPUs de Docker
   no lo aceleran. Si ns-3 no da abasto, los frames del visor llegan tarde; la
   interpolación mide el intervalo real y estira el movimiento (fluido pero más lento
   que tiempo real). Palancas: `--sumo-updates=0.1`, `--penetrationRate=0.5` (menos
   nodos radio sin quitar vehículos de SUMO), `--met-sup=false`, sin `--csv-log`.

Guía de `APP_STEP_LENGTH`: flotas pequeñas (<50) → 0.2–0.5; flotas grandes → **0.5–1.0**
(menos frames y menos payload WS por segundo simulado; la interpolación se encarga de
la suavidad).

## 6. Qué ofrece el visor durante la corrida

Vehículos 3D procedurales a su tamaño y rumbo reales; calles coloreadas por nivel de
servicio (LOS A–F) según densidad en vivo; semáforos sincronizados con las fases de SUMO;
**clic derecho** sobre un vehículo/calle/semáforo para el inspector (velocidad, CO₂,
combustible, ruido, tiempo perdido, carril, progreso de ruta…); panel de **Históricos**
(vehículos por tipo, CO₂ de flota, tiempo de viaje, esperas); capa de calles concurridas;
presets de iluminación (amanecer/día/atardecer/noche) y cámara 2D/3D con órbita. El
botón difuminado **⛶** (arriba a la derecha) oculta todos los paneles y controles —
modo presentación con solo el mapa y la simulación; otro clic los restaura.

Nota: el visor muestra la *verdad terreno* de SUMO (todos los vehículos). La percepción
por radio (CAMs recibidos por cada nodo) se analiza con los `.pcap`/CSV de ns-3 o con el
GEO SUMO WEB de la práctica (:8090).

## 7. Editar código y recompilar

El árbol vive en el volumen `van3twin_ns3-workspace` y **se edita directamente ahí**,
dentro del contenedor (`docker compose exec van3twin bash` + nano/vim, o VS Code con la
extensión *Dev Containers* adjuntada al contenedor `van3twin` — ruta
`/home/vanet/VaN3Twin/ns-3-dev`).

**Después de editar, según el tipo de fichero:**

| Qué editaste | Qué hacer después |
|---|---|
| C++ (`src/**/*.cc`, `*.h`) | `./ns3 build` (incremental) → relanzar la simulación (Paso A-B-C) |
| `CMakeLists.txt` o ejemplo nuevo | `./ns3 build` (re-ejecuta cmake solo) → relanzar |
| Escenario SUMO (`.rou.xml`, `.sumocfg`, `.net.xml`) | Nada que compilar: relanzar la simulación. Si cambió el **net**, también `up -d` del stack SUMO-GEO (el backend carga la geometría al arrancar) |
| Backend SUMO-GEO (Mac, `backend/`) | `cd ~/van3twin-docker && docker compose --profile visor build backend && docker compose --profile visor up -d` |
| Frontend SUMO-GEO (Mac, `frontend/`) | Nada: recargar el navegador (nginx lo sirve montado). Si el cambio no aparece: **recarga dura `Cmd+Shift+R`** (descarta el `app.js` cacheado) |

**Copia de seguridad:** las ediciones viven SOLO en el volumen — `docker compose down -v`
las borra. Para versionar: el árbol tiene git dentro
(`cd ~/VaN3Twin/ns-3-dev && git add -A src/automotive src/traci && git commit -m "..."`)
o exporta ficheros puntuales a `~/results` (visible en el Mac).

**Nunca** montar el árbol como bind mount del Mac ni compilar desde una carpeta APFS:
los pares de ficheros que solo difieren en mayúsculas (`ActionID/ActionId`,
`BOOLEAN/boolean`…) colisionan y rompen la compilación.

## 7b. Replay offline: intercambio de mensajes V2X desde los .pcap

Reproduce una corrida **grabada** en el visor 3D con el intercambio de mensajes real:
pulso radial en cada transmisión, arco TX→RX por cada recepción (color por tipo:
CAM azul, CPM verde, DENM rojo) y, con **clic izquierdo sobre un pulso**, el
**contenido ASN.1 completo** del mensaje (posición, velocidad, contenedores…) más la
lista de receptores. No necesita SUMO ni TraCI: la movilidad se reconstruye de los
encabezados GeoNetworking y los mensajes se decodifican con los `.asn` oficiales ETSI
del árbol de VaN3Twin.

**Flujo:**

```bash
# 1) Correr el EVA como siempre (Modo A o B — los .pcap se generan igual)
# 2) Publicar los pcaps de la corrida (dentro del contenedor):
cp ~/VaN3Twin/ns-3-dev/v2v-EVA-*.pcap ~/results/
# (nada más: el backend detecta automáticamente los ficheros nuevos de
#  ~/results al pulsar Replay o consultar /api/replay/info y recarga el índice)
```

En el visor, los controles viven en el **panel "Replay V2X"** (columna izquierda,
debajo del panel SUMO·GEO): botón 🎞 Replay pcap, línea de tiempo con seek, botones
**⏸/▶** (play/pausa) y **⏮/⏭** (paso atrás/adelante: salta un frame y pausa, con los mensajes congelados en
pantalla; clic sobre cualquier **pulso o arco** abre la **disección por capas** estilo
Wireshark — 802.11 → GeoNetworking → BTP-B → ITS/ASN.1, secciones plegables con
scroll), selector de vehículo emisor (All/vehX — al elegir uno, el vehículo se resalta con un anillo ámbar en el mapa) y filtros CAM/CPM/DENM. Debajo aparece el
panel **PHY 802.11p** con las métricas de capa física de la corrida: banda/canal/BW/
modulación y potencia TX (config. del EVA), latencia TX→RX medida (media/p95/máx),
rango de cobertura observado (p50/p95/máx), PER global (RX logradas vs esperadas
según coexistencia), PDR mejor/peor par, tasas por tipo y utilización de canal
estimada por airtime. Los **enlaces (arcos) llevan etiqueta con la distancia en
metros** entre emisor y receptor (visible en modo paso/pausa o con pocos arcos; se
ocultan con el check **m/dBm** del panel Replay), y el popup lista cada receptor con
su distancia. La potencia RX por trama no viene en los
pcap (sin radiotap), pero si copias a `~/results` un `signal-rx.csv` generado con los
callbacks SignalInfo del EVA (formato `rx,tx,t_ms,rssi[,snr]` — procedimiento y código
en `Practica_Replay_V2X.pdf`), el replay lo ingiere solo y añade el RSSI a las
etiquetas de los enlaces, a los receptores del popup y al panel PHY. Los paneles se auto-ocultan a su barra de título; el **📌** del
título los fija. Estadísticas globales (totales,
PDR por par): `curl localhost:8000/api/replay/info` (desde el Mac).

**El uso didáctico completo — incluido el análisis de los mismos pcaps con Wireshark y
el contraste entre ambas vistas — está en la práctica aparte:
`Practica_Replay_V2X.pdf`.**

Notas técnicas: la movilidad sale de la posición del emisor en cada paquete (~10 Hz —
suficiente; vehículos que nunca transmiten no aparecen); el pool de nodos de ns-3 se
reutiliza entre vehículos y el replay lo resuelve por segmentos temporales decodificando
los CAM; los arcos RX se muestrean a ≤400 por frame para no saturar; los GN Beacon
(sin payload) se excluyen. Decodificación validada con SUMO 1.12 + VaN3Twin ago-2026:
CAM (EN 302 637-2), CPM v2 (`CPM-all.asn` — no usar la variante TR103562+ISO 19091,
tarda minutos en compilar), DENM.

## 8. Solución de problemas

| Síntoma | Causa | Solución |
|---|---|---|
| Visor en negro, sin mapa | Backend caído o sin responder | `docker compose logs backend` (desde `~/van3twin-docker`); `curl localhost:8000/api/health` |
| `waiting for 2 clients` eterno | El visor no conectó | Recargar `localhost:8081`; ver logs del backend |
| Solo 1 `client connected` y visor en negro | Backend conectando a un puerto sin SUMO | Verificar `APP_SUMO_PORT_SCAN=10` en el compose; ¿corrida vieja ocupando puertos? → Paso A |
| `Invalid command-line arguments` | Flag inexistente o binario sin recompilar | `./ns3 build` tras editar; revisar nombre del flag |
| Simulación arranca sin esperar al visor | Faltó `--num-traci-clients=2` | Relanzar con el flag |
| Mapa base de Cuenca en vez de Turín | Backend viejo sin el fix de `geo.py` | `--profile visor build backend` + `up -d` |
| Vehículos congelados, Terminal sin avanzar | El visor se cerró/recargó a mitad | Paso A → B → C |
| Error de versión TraCI en logs backend | Pines ≠ SUMO del contenedor | `requirements-van3twin.txt` debe pinar la versión del `sumo --version` del contenedor (hoy 1.12.0) |
| `g++ ... Killed` al compilar | RAM de la VM Docker insuficiente | Docker Desktop → Resources: RAM ≥ 1.5×CPUs (GB) |
| Error con `MakeTupleChecker` al compilar | Se compiló desde una carpeta APFS del Mac | Compilar solo en el volumen (§7) |
| El visor se comporta "como antes" tras un cambio del frontend (saltos, controles viejos…) | `app.js` cacheado por el navegador | **Recarga dura: `Cmd+Shift+R`** (Chrome/macOS). El nginx ya envía `Cache-Control: no-store`, así que tras una recarga dura no vuelve a pasar |

### 8b. Comandos de diagnóstico, en detalle

Todos se ejecutan desde `~/van3twin-docker` salvo que se indique lo contrario.

**Estado de los contenedores:**

```bash
docker compose --profile visor ps -a
```

Lista los tres servicios (`van3twin`, `backend`, `frontend`) con su STATUS. `Up` =
corriendo; `Exited (N)` = terminó/crasheó → mirar sus logs. Sin `--profile visor` los
servicios del visor no aparecen aunque existan.

**Contenedores huérfanos ocupando puertos:**

```bash
docker ps -a | grep -iE 'backend|frontend'
```

Si aparecen `sumo_geo-backend-1`/`sumo_geo-frontend-1` (del compose separado antiguo)
están reteniendo los puertos 8000/8081 y el stack unificado no puede arrancar:
`docker rm -f sumo_geo-backend-1 sumo_geo-frontend-1`.

**Logs del backend** (la herramienta principal):

```bash
docker compose logs backend | tail -20
```

Qué buscar: `[sumo_bridge] SUMO respondió en 34XX` = conexión TraCI OK aunque el puerto
haya derivado; `Connection refused`/`could not connect` = no hay SUMO esperando (falta
el Paso B o el flag `--num-traci-clients=2`); traceback de Python al arrancar = fallo
cargando la geometría (ruta `APP_NET_FILE`, volumen); errores de versión TraCI = pines
de `requirements-van3twin.txt` distintos del SUMO del contenedor.

**Salud y metadatos del backend:**

```bash
curl http://localhost:8000/api/health   # esperado: {"status":"ok","mode":"remote"}
curl http://localhost:8000/api/meta     # esperado: center ≈ [7.66, 45.06] (Turín)
```

Sin respuesta = backend caído (ver logs). Si `center` sale ≈ [-79, -2.9] (Cuenca), el
backend corre una imagen vieja sin el fix de `geo.py` → reconstruir con `--build`.

**Procesos SUMO/ns-3 colgados** (dentro del contenedor):

```bash
pgrep -a sumo                     # ¿hay SUMO vivos de corridas anteriores?
pkill -f ns3-dev-v2v; pkill sumo  # limpieza (Paso A)
```

Un SUMO huérfano retiene su puerto: la siguiente corrida deriva a 3401, 3402… (el
backend escanea hasta 3410, pero conviene limpiar).

**Verificar los parches en el volumen** (tras un `down -v` o ante dudas):

```bash
docker compose exec van3twin grep -c "num-clients" src/traci/model/traci-client.cc  # ≥1
docker volume ls | grep ns3-workspace                                               # existe
```

**En el navegador:** consola JS (⌥⌘J en Chrome) y pestaña *Network*. `"esperando al
backend… (intento N)"` en pantalla o `/api/meta` eternamente *pending* = backend sin
responder; el WebSocket `/ws/live` con mensajes `frame` fluyendo = todo sano.

### 8c. Cuándo usar `--build` (y cuándo no)

`up -d` recrea contenedores (aplica cambios de compose: variables, puertos, montajes).
`--build` además **reconstruye la imagen**: solo hace falta cuando cambian ficheros que
se *copian o instalan dentro* de la imagen.

| Cambio | ¿`--build`? | Comando |
|---|---|---|
| `backend/app/*.py`, `requirements-van3twin.txt`, `Dockerfile.van3twin` | **Sí** | `docker compose --profile visor build backend && docker compose --profile visor up -d` |
| Variables/puertos/montajes del `docker-compose.yml` | No | `docker compose --profile visor up -d` |
| Código ns-3 (vive en el volumen) | No | `./ns3 build` dentro del contenedor |
| `frontend/` de SUMO_GEO (montado en nginx) | No | recargar el navegador |
| Escenarios SUMO (`.rou.xml`, `.sumocfg`) | No | relanzar la simulación |
| `Dockerfile` de van3twin (imagen ns-3) | **Sí** | `docker compose build` (1–3 h; ojo: el volumen sigue tapando el árbol nuevo — ver documentación del stack) |

Regla rápida: si el fichero aparece en un `COPY`/`RUN` de un Dockerfile → `--build`;
si llega por volumen o variable de entorno → basta `up -d` (o nada).

> **Si un build tarda demasiado:** el del backend toma ~2-5 min la primera vez
> (descarga `python:3.11-slim` + wheels de pip) y segundos después (caché). Si en la
> salida ves gRPC, apt del toolchain o compilación de ns-3, se está reconstruyendo la
> imagen grande de van3twin por error: `Ctrl+C` (seguro — las capas cacheadas se
> conservan) y usa la forma en dos pasos: `build backend` primero, `up -d` después.
> Por eso el manual evita `up -d --build`, que según la versión de compose puede
> arrastrar dependencias al build. **Nunca ejecutes `docker compose build` sin
> argumento en este proyecto**: construye todos los servicios, van3twin incluido.
> Para máxima seguridad al levantar: `docker compose --profile visor up -d --no-build`.
> Cancelar una reconstrucción accidental es seguro: la imagen existente solo se
> reemplaza cuando el build termina.

## 9. Cierre de sesión

```bash
cd ~/van3twin-docker
docker compose --profile visor stop    # pausa todo (van3twin + visor)
# o: docker compose --profile visor down   # elimina contenedores; el volumen persiste
```

`docker compose down -v` en van3twin-docker **borra el volumen con el build de ns-3** —
no usarlo salvo que quieras reconstruir desde la imagen.

## 10. Resumen de comandos

**Primera ejecución** (construye la imagen del backend; ~2-3 min):

```bash
# si quedaron contenedores del antiguo compose separado, retirarlos una única vez:
docker rm -f sumo_geo-backend-1 sumo_geo-frontend-1 2>/dev/null

cd ~/van3twin-docker
docker compose --profile visor build backend && docker compose --profile visor up -d   # van3twin + visor
docker compose exec van3twin bash
# ── dentro del contenedor ──
pkill -f ns3-dev-v2v; pkill sumo; sleep 1
./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true --sumo-updates=0.1 --num-traci-clients=2"
#   -> "waiting for 2 clients... client connected" y se queda esperando
# ── en el navegador ──  http://localhost:8081  -> arranca el lockstep
```

**Resto de ejecuciones:**

```bash
cd ~/van3twin-docker
docker compose --profile visor up -d       # solo si no está ya arriba
docker compose exec van3twin bash
# ── dentro del contenedor ──
pkill -f ns3-dev-v2v; pkill sumo; sleep 1
./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true --sumo-updates=0.1 --num-traci-clients=2"
# ── en el navegador ──  recargar http://localhost:8081
```

Nueva corrida en la misma sesión: `Ctrl+C` → `pkill` → relanzar → recargar la página.
Al terminar la jornada: `docker compose --profile visor stop`.
Tras editar código: ver la tabla del §7 (C++ → `./ns3 build`; backend →
`--profile visor build backend` + `up -d`; escenario SUMO → solo relanzar).

---

*Documentos relacionados: `GUIA_INTEGRACION_SUMO_GEO.md` (diseño original de la
integración), `CONTEXTO_VAN3TWIN.md` y `CONTEXTO_SUMO_GEO.md` (estado técnico de cada
proyecto y correcciones aplicadas sobre la guía).*
