# Contexto: mejoras del visor 3D (sesión 29-ago-2026) — insumo para práctica

> **Propósito**: resumen autocontenido de las mejoras añadidas al visor SUMO-GEO
> en la sesión Cowork del 29-ago, pensado como insumo para redactar una nueva
> práctica de laboratorio. Complementa `CONTEXTO_SUMO_GEO.md` (detalle técnico
> por fichero) y sigue el estilo de `Practica_Replay_V2X.tex`.
> Estilo LaTeX institucional: azul #002856 / rojo #A51008, pdflatex ×2.

---

## 1. Origen e inspiración (marco para la práctica)

Se evaluó el repo **`bilawalsidhu/gods-eye-view`** (visor OSINT de "satélite
espía": CesiumJS + Vite, licencia **MIT** — código libre; sus datos/modelos 3D
tienen licencias propias). No es integrable directo (motor distinto:
MapLibre+deck.gl sin build step vs Cesium+Vite), así que se **portaron
patrones**, no código:

| Patrón gods-eye-view | Adaptación en SUMO-GEO |
|---|---|
| Cockpit view (cámara dentro de un avión) | Cámara persecución de vehículo SUMO |
| Reskin reality (shaders CRT/NVG/FLIR) | Filtros CSS sobre `#map` + scanlines |
| Detection overlay (bounding boxes + IDs) | PathLayer + TextLayer sobre vehículos |
| "Render one interval behind" (suavidad) | Estiramiento de ventana de interpolación |
| World-stable icons | **NO aplicaba**: nuestros vehículos ya son geometría 3D orientada por rumbo real (`partRect(d.angle)`), no sprites 2D |

Punto didáctico: reutilizar *enfoques* de un proyecto open source respetando
que MIT cubre el código, no los assets.

## 2. Features nuevas (qué son y cómo se usan)

Todas en `SUMO_GEO/frontend/` (recarga = deploy; nginx sirve `no-store`),
salvo las marcadas **[backend]** (requieren `docker compose --profile visor
build backend && ... up -d`).

1. **Cámara cockpit / seguimiento**: clic derecho sobre un vehículo →
   "🎥 Seguir este vehículo" → la cámara lo persigue (pitch 76°, zoom 19.3,
   orientada a su rumbo) con badge flotante (id, rumbo, km/h en vivo).
   Salir: ✕, arrastrar el mapa, o el pad. Funciones: `startFollow/stopFollow/
   updateFollowCamera` (llamada en cada tick de interpolación).
2. **Modos sensor** (selector en topbar): Normal / NVG / FLIR / Noir / CRT.
   Filtro CSS sobre `#map` (mapa y overlay deck.gl comparten elemento); CRT
   añade scanlines+viñeta (`#scanlines`, `body[data-sensor="crt"]`).
3. **Detección (HUD)** (checkbox del panel, ahora sobre "Calles concurridas"):
   caja verde + etiqueta `veh<station>` sobre cada vehículo — ilustra "qué ve"
   un nodo V2X con percepción. Capas `detect-box`/`detect-label` en el refresco
   dinámico; gateado por `LOD_MAX_DETAILED`.
4. **Barra de tiempo del replay**: track con relleno de progreso, thumb
   estilo reproductor, tiempos `m:ss` actual/total.
5. **Velocidad del replay** (🐢 1× 🐇): multiplicador 0.25–4× sobre **tiempo
   real**. **[backend]** El cmd WS `speed` acepta `step`: el visor pide
   cadencia fija 10 fps con avance simulado `mult/10` s/frame (1× = 0.1 s =
   granularidad de un CAM a 10 Hz).
6. **Pulso TX = alcance real**: el anillo de transmisión se expande hasta
   `range_m.p95` medido de la corrida (panel PHY); desvanecimiento suave
   (alfa 220→30 %) y trazo 3.2 px. Física visible: el círculo ES la cobertura.
7. **TTL por tipo de evento**: arco RX 2.6 s (inspeccionable con clic),
   pulso TX 1.2 s.
8. **Arcos anclados a los vehículos dibujados**: pulsos/arcos se re-anclan por
   `station` a la posición interpolada en cada tick (antes usaban la posición
   cruda del frame y se "adelantaban").
9. **Mensajes V2X EN VIVO** **[backend]**: durante una corrida VaN3Twin, el
   backend relee en caliente los pcap que ns-3 escribe en su workdir (volumen
   ya montado RO en `/ns3`; `APP_LIVE_PCAP_DIR=/ns3/ns-3-dev`) y adjunta los
   eventos TX/RX a los frames en vivo. El visor revela automáticamente
   "Mensajes V2X", filtros CAM/CPM/DENM, filtro **Emisor** y el **panel PHY de
   la corrida en curso** (`/api/replay/info?live=1`, refresco 10 s).
   - dBm: del `signal-rx.csv` que el EVA parcheado vuelca en el mismo dir.
   - metros: distancia entre posiciones TraCI en vivo de emisor y receptor.
   - Retraso de unos segundos por buffering de escritura de ns-3 (honesto:
     documentarlo en la práctica).
10. **Filtro por emisor en ambos modos**: fila propia "Emisor" (`#row-veh-filter`);
    en vivo se puebla sola con las estaciones que aparecen; anillo ámbar sobre
    el emisor seleccionado.
11. **Limpieza UI**: selector "Escenario" eliminado (solo aplicaba a managed).
12. **Vehículos 3D glTF** (sesión 29-ago, tarde): sedán/bus/ambulancia low-poly
    (`frontend/models/*.glb`, ~300 tris, generados proceduralmente — sin
    licencias de terceros) renderizados con `ScenegraphLayer` instanciada en
    GPU: mejor estética Y mejor rendimiento que las cajas (que se regeneraban
    en CPU cada tick). Sedán tintado por la paleta por-vehículo; fallback
    automático a las cajas si falla la carga o con >3000 vehículos. Requiere
    el script extra `@loaders.gl/gltf` en index.html (deck.gl 9 no trae el
    GLTFLoader en su bundle). Punto didáctico: instancing GPU vs geometría CPU.

## 3. Bugs diagnosticados y corregidos (ORO didáctico para la práctica)

Cada uno es un mini-caso de depuración real con causa no obvia:

1. **Movimiento avanza-y-para**: `interpPeriod` es una MEDIA móvil del
   intervalo entre frames → la mitad de los frames llegan más tarde que la
   media (jitter) y el vehículo agotaba su interpolación y esperaba parado.
   Fix: `INTERP_STRETCH=1.30` (ventana estirada; cada frame reinicia desde la
   posición dibujada → se autocorrige sin saltos). Concepto: interpolación con
   retardo vs extrapolación; jitter de red.
2. **Replay 5× más rápido que la realidad**: 10 fps × 0.5 s/frame = 5 s
   simulados/s. En vivo no se nota porque ns-3 (lockstep) marca el ritmo.
   Fix v1: 2 fps (correcto pero robótico). Fix v2: desacoplar render (10 fps)
   de avance simulado (`step` variable). Concepto: tiempo de simulación vs
   tiempo de pared vs cadencia de render.
3. **"Seguir vehículo" se autocancelaba**: `map.jumpTo()` dispara
   `rotatestart` TAMBIÉN programáticamente; el handler "cancelar al rotar"
   mataba el seguimiento en el primer frame de la propia cámara. Fix: guard
   `e.originalEvent` (gesto real vs evento programático).
4. **Botón inclickeable en el popup**: heredaba `pointer-events:none` del
   popup no interactivo. Fix: `pointer-events:auto` inline.
5. **Pausas periódicas en vivo (regresión)**: el bucle de frames hacía
   `await` del re-parse del índice V2X; como el pcap crece, la huella cambiaba
   en cada chequeo → stream congelado ~0.5 s cada ~2 s. Fix: caché sin
   bloqueo (`_live_rep_nowait`) + reconstrucción en tarea de fondo con
   throttle adaptativo (3× la duración real del parse). Concepto: event loop
   asyncio, nunca bloquear el camino caliente, trabajo CPU-bound a threads.
6. **Arcos adelantados**: posiciones crudas del frame vs vehículos
   interpolados (~medio período atrás). Fix: re-anclaje por station en cada
   tick de render.

## 4. Ficheros tocados

| Fichero | Cambios |
|---|---|
| `frontend/app.js` | cockpit, sensores, detección, barra/velocidad replay, TTLs, pulso-alcance, re-anclaje, V2X en vivo (UI), filtro emisor, INTERP_STRETCH |
| `frontend/index.html` | badge follow, selector sensor, checkbox detección, barra tiempo, fila velocidad, fila Emisor, sin "Escenario", `#scanlines` |
| `frontend/style.css` | estilos de todo lo anterior (tokens UCuenca) |
| `backend/app/main.py` | `speed{step}` en replay; live V2X: `_live_build/_live_refresh_bg/_live_rep_nowait`, `?live=1`, station en vehículos, dedup `sent_v2x` |
| `backend/app/config.py` | `live_pcap_dir`, `live_refresh_s` |

## 5. Procedimiento de verificación (base para los ejercicios)

1. Rebuild backend (una vez): `docker compose --profile visor build backend && docker compose --profile visor up -d`.
2. **En vivo**: lanzar EVA (`./ns3 run "v2v-emergencyVehicleAlert-80211p
   --sumo-gui=false --met-sup=true --sim-time=300 --num-traci-clients=2"`),
   abrir el visor → a los pocos segundos brotan pulsos/arcos, aparecen los
   filtros y el panel PHY va creciendo con la corrida.
3. **Cockpit**: clic derecho en un vehículo → Seguir; comprobar rumbo/km-h.
4. **Detección**: activar checkbox; comparar station del HUD con el filtro Emisor.
5. **Sensores**: ciclar NVG/FLIR/CRT (útil para capturas de la práctica).
6. **Replay**: copiar pcaps+csv a `~/results`, entrar en Replay: barra m:ss,
   1× realista, 🐢/🐇, paso a paso con arcos congelados clicables.
7. Medir con el alumno: radio final del pulso ≈ `Cobertura p95` del panel PHY.

## 6. Ideas de ejercicios para la práctica

- Comparar la MISMA corrida en vivo y en replay: ¿por qué el replay puede ir a
  4× y el vivo no? (quién marca el reloj).
- Con el filtro Emisor + cockpit: seguir a la ambulancia y observar sus DENM.
- Estimar el exponente de path-loss n con las etiquetas "m · dBm" de varios
  arcos y compararlo con LogDistance n=3.0 (ya hay teoría en Practica_Replay).
- Depuración guiada: reproducir el bug del rotatestart programático comentando
  el guard `originalEvent` (efecto inmediato y visible).
- ¿Por qué los arcos en vivo tardan ~2-4 s en aparecer? (buffering de
  PcapFileWrapper → cadena captura→disco→parser→WS→render).

## 7. Pendientes al redactar la práctica

- [x] Decisión tomada (29-ago): **documento aparte** — `Practica_Visor_V2X_Tiempo_Real.tex/pdf`
      (8 págs), con Replay + instalación como prerrequisitos. `Practica_Replay_V2X`
      quedó intacta. Estructura: marco teórico (3 relojes, jitter/INTERP_STRETCH,
      cadena en vivo con diagrama, patrones vs código/MIT), partes 1-5 (vivo,
      cockpit, HUD, sensores, replay mejorado), 6 casos de depuración en cajas
      `casobox`, 7 ejercicios (usa las ideas de §6), entregables.
- [ ] `git push` de SUMO_GEO y van3twin-docker con todos estos cambios.
- [ ] Capturas nuevas para la práctica (en el Mac — el modo vivo no es
      reproducible en sandbox) e insertarlas en el .tex.
