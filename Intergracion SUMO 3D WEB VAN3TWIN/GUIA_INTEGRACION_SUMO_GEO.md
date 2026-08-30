# Guía: ejecutar SUMO-GEO (visor 3D web) junto a VaN3Twin

**Objetivo:** que el frontend MapLibre/deck.gl de [SUMO_GEO](https://github.com/Pbarbecho/SUMO_GEO)
visualice en 3D, en tiempo real, **la misma simulación SUMO que controla VaN3Twin** (ns-3).

**Mecanismo:** TraCI **multi-cliente**. VaN3Twin arranca SUMO con `--num-clients 2` y se
conecta como cliente **1**; el backend de SUMO-GEO (modo `remote`) se conecta como cliente **2**
y solo lee (suscripciones). SUMO avanza en *lockstep*: exige que ambos clientes pidan paso.

```
┌────────────── contenedor van3twin ──────────────┐      red docker      ┌───── stack SUMO-GEO ─────┐
│ ns-3 (EVA) ──TraCI #1 (setOrder 1)──► SUMO      │◄─── van3twin_default │ backend FastAPI          │
│             --num-clients 2, puerto 1338        │      TraCI #2        │ (remote, setOrder 2)     │
└─────────────────────────────────────────────────┘   (setOrder 2, RO)   │   │ WS/REST              │
                                                                         │ nginx :8081 ◄── browser  │
                                                                         └──────────────────────────┘
```

## Hechos validados empíricamente (sandbox, SUMO 1.27 + traci)

1. **Lockstep sin deadlock**: cliente 1 con pasos finos (0,1 s) + cliente 2 pidiendo objetivos
   gruesos (`simulationStep(t_actual + 1.0)`) → el visor **no frena** a ns-3.
2. **El handshake del cliente 1 se bloquea** hasta que conecta el cliente 2. Es decir:
   ns-3 quedará "esperando" tras lanzar la simulación hasta que abras el visor. Normal.
3. `setOrder(1)` es **inocuo** con un solo cliente → el parche de VaN3Twin no rompe el uso normal.
4. SUMO escucha TraCI en `0.0.0.0` → alcanzable desde otro contenedor **sin publicar puertos**
   (basta compartir red docker).

---

## Paso 1 — Parche VaN3Twin: llamar `setOrder(1)` tras conectar

`src/traci/model/traci-client.cc` **nunca** llama a `setOrder()` (la API sí lo implementa,
`sumo-TraCIAPI.cc:87`). Sin esto, SUMO multi-cliente no sabe el orden y se bloquea.

Dentro del contenedor (persiste en la carpeta local `van3twin-docker/VaN3Twin` del Mac):

```bash
cd ~/van3twin-docker && docker compose up -d
docker compose exec van3twin bash

# dentro del contenedor:
cd ~/VaN3Twin/ns-3-dev
sed -i '/this->TraCIAPI::connect("localhost", m_sumoPort);/a\
        if (m_sumoAddCmdOpt.find("--num-clients") != std::string::npos) { this->TraCIAPI::setOrder(1); }' \
  src/traci/model/traci-client.cc
./ns3 build          # recompila solo el módulo traci y dependientes
```

El parche queda **condicionado**: solo llama `setOrder(1)` si pediste `--num-clients` (cero
cambios de comportamiento en el uso normal). Punto de inserción: justo después de
`TraCIAPI::connect("localhost", m_sumoPort)` (línea ~282).

*Opción permanente:* añade ese mismo `sed` como capa `RUN` en el `Dockerfile` de
`van3twin-docker` (antes de la capa de configure/build) y reconstruye con `REBUILD_NS3`.

## Paso 2 — Backend SUMO-GEO: `setOrder(2)` + paso con objetivo absoluto

Dos ficheros del repo `SUMO_GEO`:

**`backend/app/config.py`** — añade tras `sumo_port`:

```python
    sumo_order: int = 0        # >0 => TraCI multi-cliente: llamar setOrder(N) al conectar
```

**`backend/app/sumo_bridge.py`** — rama `remote` de `start()`:

```python
        if settings.sumo_mode == "remote" and not self._libsumo:
            client.init(host=settings.sumo_host, port=settings.sumo_port)
            if settings.sumo_order:
                client.setOrder(settings.sumo_order)      # <— NUEVO
            self.conn = client
```

y en `step()` (crítico — sin esto el visor limitaría a ns-3 a 1 paso SUMO por frame):

```python
    def step(self) -> float:
        if settings.sumo_mode == "remote" and settings.sumo_order:
            # objetivo ABSOLUTO grueso: ns-3 marca el ritmo con sus pasos finos
            self.conn.simulationStep(self.conn.simulation.getTime() + settings.step_length)
        else:
            self.conn.simulationStep()
        ...resto igual...
```

Por qué: VaN3Twin lanza SUMO con `--step-length <SynchInterval>` (pasos finos). En la barrera
multi-cliente, si el visor pidiera "un paso" a 10 fps, ns-3 quedaría esclavo del visor. Con
objetivo absoluto `t+1.0 s` el visor concede margen y ns-3 avanza a su ritmo (validado).

## Paso 3 — Versiones: traci del backend = SUMO del contenedor

El contenedor van3twin lleva **SUMO 1.12.0** (apt Ubuntu 22.04); el backend pina
`traci==1.27.1`. Tu propio `requirements.txt` ya lo advierte: *"Pin these to match the SUMO
version you run"*. En modo remote **no hace falta el binario** (`eclipse-sumo`), solo las
librerías puras:

**`backend/requirements-van3twin.txt`** (nuevo):

```
fastapi==0.115.6
uvicorn[standard]==0.34.0
websockets==14.1
pydantic-settings>=2.4,<3
traci==1.12.0
sumolib==1.12.0
pyproj>=3.6
```

**`backend/Dockerfile.van3twin`** (nuevo, mínimo — sin libs X11/GL porque no hay binario SUMO):

```dockerfile
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements-van3twin.txt .
RUN pip install --no-cache-dir -r requirements-van3twin.txt
COPY app ./app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Paso 4 — `docker-compose.van3twin.yml` (raíz de SUMO_GEO)

Reutiliza la red del proyecto van3twin (`van3twin_default`; verifica con
`docker network ls`) y monta en solo lectura la carpeta local
`~/van3twin-docker/VaN3Twin` (bind mount del stack van3twin).

```yaml
services:
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile.van3twin
    environment:
      APP_SUMO_MODE: remote
      APP_SUMO_HOST: van3twin          # container_name del stack van3twin
      APP_SUMO_PORT: "1338"            # default de ns3::TraciClient::SumoPort
      APP_SUMO_ORDER: "2"
      # geometría: el MISMO net que usa el ejemplo EVA, leído del bind mount
      APP_NET_FILE: /ns3/ns-3-dev/src/automotive/examples/sumo_files_v2v_map/map.net.xml
      APP_POLY_FILE: /no_poly.xml      # inexistente a propósito: evita el fallback al .sumocfg
      APP_STEP_LENGTH: "1.0"           # objetivo de avance por frame del visor
      APP_MAX_FPS: "10"
    volumes:
      - ~/van3twin-docker/VaN3Twin:/ns3:ro   # ajustar ruta si difiere
    ports:
      - "8000:8000"
    networks: [default, van3twin]

  frontend:
    image: nginx:1.27-alpine
    volumes:
      - ./frontend:/usr/share/nginx/html:ro
      - ./frontend/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "8081:80"
    depends_on: [backend]

networks:
  van3twin:
    external: true
    name: van3twin_default
```

Notas: el frontend no cambia (nginx ya proxya `/api` y `/ws` al servicio `backend`).
`APP_POLY_FILE` inexistente es intencional: si queda vacío, `main.py` intentaría parsear
`/sumo/demo.sumocfg` (que aquí no existe). Mejora opcional en `main.py`: tolerar
`APP_POLY_FILE=""` sin fallback.

## Paso 5 — Ejecución (el orden importa)

```bash
# 1) stack van3twin arriba (si no lo está)
cd ~/van3twin-docker && docker compose up -d

# 2) lanzar la simulación EVA pidiendo 2 clientes TraCI
docker compose exec van3twin bash
./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true \
  --ns3::TraciClient::SumoAdditionalCmdOptions='--num-clients 2'"
#   -> ns-3 lanza SUMO y queda ESPERANDO al 2º cliente (hecho validado nº 2)

# 3) en el Mac: levantar SUMO-GEO en modo van3twin
cd /ruta/a/SUMO_GEO
docker compose -f docker-compose.van3twin.yml up -d --build

# 4) abrir el visor: al conectarse el WebSocket arranca todo en lockstep
open http://localhost:8081
```

`--ns3::TraciClient::SumoAdditionalCmdOptions=...` funciona sin tocar el ejemplo: es la
sintaxis estándar de ns-3 para fijar atributos desde CLI, el ejemplo EVA no fija ese
atributo, y `traci-client.cc:240` lo concatena al comando de SUMO.

## Paso 6 — Verificación

```bash
docker compose -f docker-compose.van3twin.yml logs backend   # sin errores TraCI/versión
curl http://localhost:8000/api/health
```

En el visor deben aparecer los 7–8 vehículos del EVA (mapa real del ejemplo, zona de Turín),
con inspector de clic derecho (velocidad, edge, CO₂…), LOS por calle y panel histórico.

## Límites y notas

- **Un visor por corrida**: en modo remote no uses el selector Bajo/Medio/Alto (reconecta a
  otro SUMO que aquí no existe). Si recargas la página a mitad de corrida puede hacer falta
  relanzar el paso 5.2 (`--num-clients` fija el nº de clientes al arranque).
- Al terminar la simulación, VaN3Twin cierra SUMO (`--quit-on-end`) y el visor pierde la
  conexión: es lo esperado.
- **Qué muestra cada visor**: SUMO-GEO = *verdad terreno* de SUMO en 3D (todos los vehículos);
  GEO SUMO WEB 2D/3D (carpeta de la práctica) = *percepción por radio* (CAMs por receptor);
  vehicle-visualizer (:8080) = verdad terreno 2D nativa de VaN3Twin. Complementarios.
- Puertos en uso: 8081 (frontend), 8000 (backend), 8080 (vehicle-visualizer), 5901 (VNC),
  8090 (GEO SUMO WEB vivo). TraCI 1338 no se publica: viaja por la red docker interna.
- Si algún día actualizas el SUMO del contenedor van3twin, actualiza los pines
  `traci`/`sumolib` del Paso 3 para que coincidan.
