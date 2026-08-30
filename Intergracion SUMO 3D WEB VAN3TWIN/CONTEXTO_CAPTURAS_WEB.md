# Contexto: capturas PNG del visor web para las prácticas

> Cómo se generaron las imágenes de `img/` (usadas en `Practica_Replay_V2X.tex`)
> y cómo reproducirlas/ampliarlas en futuras prácticas. Script reutilizable:
> `tools/captura_web.py`. Método validado el 28-ago-2026 en el sandbox de Claude.

## Idea general

No se capturan del Chrome del usuario (esas imágenes no pueden guardarse como
ficheros): se corre el **stack completo en el sandbox Linux** — backend FastAPI en
modo replay + frontend estático servidos en el mismo puerto — y un **Chromium
headless (Playwright)** navega, entra en replay, congela un paso y fotografía cada
panel por separado (`locator(sel).screenshot()` recorta el elemento exacto). Los PNG
se escriben directamente en `img/` de esta carpeta, a `device_scale_factor=2`
(nítidos en el PDF).

## Setup en el sandbox (una vez por sesión)

1. `pip install playwright --break-system-packages && python3 -m playwright install chromium`
   (sin `--with-deps`: no hay sudo).
2. Falta una librería del sistema; sin sudo se resuelve extrayéndola en local:
   ```bash
   mkdir -p ~/libs && cd ~/libs && apt-get download libxdamage1
   dpkg -x libxdamage1*.deb ~/libs/root
   export LD_LIBRARY_PATH=~/libs/root/usr/lib/aarch64-linux-gnu   # sandbox es aarch64
   ```
3. Lanzar Chromium siempre con `args=["--no-sandbox"]`. WebGL funciona (SwiftShader):
   MapLibre + deck.gl renderizan el mapa completo. `unpkg.com` y
   `tiles.openfreemap.org` son alcanzables desde el sandbox (CDNs del frontend).

## Servidor combinado (frontend + backend same-origin)

El frontend espera `/api` y `/ws` en su mismo origen (en producción lo hace nginx).
Para las capturas basta montar los estáticos sobre la app FastAPI (`/tmp/serve.py`):

```python
import sys; sys.path.insert(0, "<SUMO_GEO>/backend")
from fastapi.staticfiles import StaticFiles
from app.main import app
app.mount("/", StaticFiles(directory="<SUMO_GEO>/frontend", html=True), name="static")
```

Variables antes de `uvicorn serve:app --port 8780`: las mismas del compose
(`APP_SUMO_MODE=remote`, `APP_NET_FILE=<árbol>/map.net.xml`, `APP_POLY_FILE=/no_poly.xml`,
`APP_REPLAY_DIR=<dir con pcaps>`, `APP_REPLAY_PATTERN='v2v-EVA-*.pcap'`,
`APP_ASN_DIR=<árbol>/ASN1`, `APP_STEP_LENGTH=0.5`). Los pcap se leen del espejo
`~/van3twin-docker/VaN3Twin/ns-3-dev` (símlinks a un dir temporal); si se quiere RSSI
en las capturas, generar un `signal-rx.csv` sintético desde los eventos (ver script en
el historial) o usar uno real.

## Los 5 trucos que hacen que salga bien (aprendidos a golpes)

1. **Forzar paneles abiertos**: los paneles se auto-colapsan; quitar la clase no basta
   (algo los recolapsa). Inline gana a la clase:
   `p.classList.remove('collapsed'); p.style.maxHeight='none'` (const `FORCE` del script).
2. **Pausar inmediatamente tras el seek**: si no, el servidor sigue reproduciendo
   durante los waits y llega al FINAL de la corrida — y los pasos en t=t1 devuelven
   ventanas de mensajes **vacías** (síntoma: `msgEvents.length == 0`).
3. **Interactuar por `evaluate`, no por UI**, para lo no clicable en headless:
   seek (`s.value=80; s.dispatchEvent(new Event('input'))`), selector de vehículo,
   zoom (`map.jumpTo({center:[v.lon,v.lat], zoom:17.2, pitch:55})` con `v` de la
   global `vehicles`), y el popup (elegir evento de `msgEvents` y
   `send({cmd:'inspect', station, t, mtype})` + posicionar `#popup` a mano).
4. **Esperas por función, no por tiempo**: `vehicles.length>0`, texto `Latencia` en
   `#phy-body`, texto `ITS` en `#popup`.
5. **`/tmp` del sandbox es volátil entre llamadas** de bash: regenerar dir de pcaps y
   CSV dentro de la misma llamada, y servidor+navegador deben vivir en UNA llamada
   (los procesos en background no sobreviven).

## Capturas producidas (en `img/`)

`visor_general.png` (página completa con pulsos), `panel_sumogeo.png`,
`panel_replay.png`, `panel_phy.png`, `panel_historicos.png`,
`replay_paso.png` (zoom al emisor seleccionado, paso congelado, arcos con etiquetas
distancia·RSSI), `popup_mensaje.png` (disección por capas + ASN.1).

Para nuevas capturas: ajustar `--seek/--station/--zoom` en `tools/captura_web.py`, o
añadir screenshots de otros elementos con `pg.locator("#id").screenshot(...)`.
En LaTeX: `\includegraphics[width=...]{img/nombre.png}`.
