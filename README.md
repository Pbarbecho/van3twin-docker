# van3twin-docker — VaN3Twin + visor 3D SUMO-GEO (integración V2X)

Stack Docker para ejecutar **VaN3Twin** (framework V2X sobre ns-3, ejemplo EVA
802.11p) con movilidad SUMO y visualizarlo **en vivo y en 3D en el navegador**
mediante **SUMO-GEO** (MapLibre/deck.gl), acoplados a la misma instancia de
SUMO por TraCI multi-cliente. Incluye además un modo **replay offline**: los
`.pcap` de una corrida se reproducen sobre el mapa con el intercambio de
mensajes real (CAM/CPM/DENM), disección ASN.1 por capas, distancia/RSSI por
enlace y estadísticas de capa física.

Desarrollado en la Universidad de Cuenca — Redes Vehiculares y Heterogéneas
(INGE-00104). Probado en macOS Apple Silicon (imagen **arm64**).

## Los tres repositorios

| Repo | Contenido | Rol |
|---|---|---|
| **este** (`van3twin-docker`) | Dockerfile, `docker-compose.yml` unificado, manuales, práctica, contextos, herramientas | Punto de entrada: orquesta todo |
| [`Pbarbecho/VaN3TwinGEO`](https://github.com/Pbarbecho/VaN3TwinGEO) | Fork de VaN3Twin (ns-3) **con los parches de la integración** en `master` (TraCI multi-cliente `setOrder`, flag `--num-traci-clients`, log RSSI SignalInfo) | Código ns-3 |
| [`Pbarbecho/SUMO_GEO`](https://github.com/Pbarbecho/SUMO_GEO) | Visor web: backend FastAPI (modos managed/remote/**replay**) + frontend MapLibre/deck.gl | Código del visor |

## Contenido de este repo

```
docker-compose.yml      compose UNIFICADO: servicio van3twin + profile "visor"
                        (backend remote + frontend nginx del repo SUMO_GEO)
Dockerfile              imagen van3twin:jammy (ubuntu 22.04 arm64, SUMO 1.12,
                        gRPC, NetAnim, ns-3 compilado dentro)
Intergracion SUMO 3D WEB VAN3TWIN/
  Manual_Simulacion_VaN3Twin_SUMO_GEO.pdf   manual de operación completo
  Practica_Replay_V2X.pdf                   práctica: replay web vs Wireshark,
                                            teoría CAM/DENM/CPM/ASN.1/RSSI
  CONTEXTO_*.md                             estado técnico para retomar el trabajo
  img/, tools/                              capturas del visor y script que las genera
RESPALDO.md             plan de respaldo y réplica
results/                salidas de simulación (bind mount del contenedor)
```

## Replicar desde cero

1. **Clonar los repos** (⚠️ el fork de ns-3 **nunca** en una carpeta APFS normal
   de macOS: el repo tiene ficheros que solo difieren en mayúsculas —
   `ActionID/ActionId`, `BOOLEAN/boolean` — y colisionan; en este stack el
   árbol vive en un volumen Docker, que es case-sensitive):

   ```bash
   git clone https://github.com/Pbarbecho/van3twin-docker.git
   git clone https://github.com/Pbarbecho/SUMO_GEO.git
   ```

2. **Ajustar rutas del compose**: los servicios del visor referencian el repo
   `SUMO_GEO` con ruta absoluta (`build.context` del backend y los montajes del
   frontend). Editar esas tres rutas en `docker-compose.yml` para que apunten a
   donde se clonó `SUMO_GEO`.

3. **Imagen van3twin con los parches incluidos**: en el `Dockerfile`, cambiar
   la URL del `git clone` a `https://github.com/Pbarbecho/VaN3TwinGEO.git`
   (el `VAN3TWIN_REF: master` del compose ya vale, los parches están en
   master). Después:

   ```bash
   cd van3twin-docker
   docker compose build            # 1-3 h la primera vez
   ```

4. **Levantar y probar**:

   ```bash
   docker compose --profile visor up -d       # van3twin + visor (:8081)
   docker compose exec van3twin bash
   ./ns3 run "v2v-emergencyVehicleAlert-80211p --sumo-gui=false --met-sup=true --sumo-updates=0.1 --num-traci-clients=2"
   # -> "waiting for 2 clients"; abrir http://localhost:8081 y arranca el lockstep
   ```

## Uso diario (resumen)

```bash
docker compose up -d                       # solo VaN3Twin (Modo A)
docker compose --profile visor up -d       # VaN3Twin + visor 3D (Modo B)
# replay de una corrida grabada:
docker compose exec van3twin bash -c 'cp ~/VaN3Twin/ns-3-dev/v2v-EVA-*.pcap ~/results/'
# -> botón "Replay pcap" en http://localhost:8081 (el backend detecta los ficheros solos)
```

El flujo completo (pasos A-B-C, modo paso a paso, panel PHY, RSSI real con
`signal-rx.csv`, solución de problemas) está en
`Intergracion SUMO 3D WEB VAN3TWIN/Manual_Simulacion_VaN3Twin_SUMO_GEO.pdf`;
el uso didáctico con Wireshark, en `Practica_Replay_V2X.pdf`.

## Licencias

VaN3Twin/ns-3: GPL-2.0 (upstream [DriveX-devs/VaN3Twin](https://github.com/DriveX-devs/VaN3Twin)).
SUMO-GEO y estos materiales: uso docente, Universidad de Cuenca.
