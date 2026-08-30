#!/usr/bin/env python3
"""Capturas PNG del visor SUMO-GEO (modo replay) para las prácticas.

Corre el stack COMPLETO en local (backend FastAPI + frontend estático en el
mismo puerto) y un Chromium headless (Playwright) que navega, entra en modo
replay, congela un paso y fotografía cada panel y escena por separado.

Uso (ver CONTEXTO_CAPTURAS_WEB.md para el setup completo):
    python3 captura_web.py --out ./img --seek 80 --station 0

Requisitos: playwright + chromium instalados; los pcap (y signal-rx.csv
opcional) en REPLAY_DIR; variables APP_* del backend ya exportadas; el
servidor combinado corriendo (uvicorn serve:app) en --url.
"""
import argparse

from playwright.sync_api import sync_playwright

FORCE = ("document.querySelectorAll('#panel,#replay-panel,#phy-panel,#histpanel')"
         ".forEach(p=>{p.classList.remove('collapsed');"
         " p.style.maxHeight='none'; p.style.transition='none';})")

ap = argparse.ArgumentParser()
ap.add_argument("--url", default="http://localhost:8780/")
ap.add_argument("--out", default="./img")
ap.add_argument("--seek", type=float, default=80.0)
ap.add_argument("--station", default="0", help="stationID a resaltar/filtrar")
ap.add_argument("--zoom", type=float, default=17.2)
a = ap.parse_args()

with sync_playwright() as p:
    b = p.chromium.launch(args=["--no-sandbox"])
    pg = b.new_page(viewport={"width": 1500, "height": 950},
                    device_scale_factor=2)
    pg.goto(a.url, wait_until="load")
    pg.wait_for_selector("#panel", timeout=15000)
    pg.wait_for_timeout(4000)                       # CDNs (unpkg) + mapa base
    pg.click("#btn-replay")
    pg.wait_for_selector("#replay-bar", state="visible", timeout=30000)
    pg.wait_for_function(
        "typeof vehicles!=='undefined' && vehicles.length>0", timeout=60000)
    try:
        pg.wait_for_function(
            "document.getElementById('phy-body').innerText.includes('Latencia')",
            timeout=45000)
    except Exception:
        print("aviso: panel PHY sin cargar")
    pg.wait_for_timeout(3000)                       # tráfico y pulsos en marcha

    # --- vistas generales y paneles (forzados a expandido) -------------------
    pg.evaluate(FORCE); pg.wait_for_timeout(400)
    pg.screenshot(path=f"{a.out}/visor_general.png")
    for sel, name in [("#panel", "panel_sumogeo"), ("#replay-panel", "panel_replay"),
                      ("#phy-panel", "panel_phy"), ("#histpanel", "panel_historicos")]:
        pg.locator(sel).screenshot(path=f"{a.out}/{name}.png")

    # --- seek + PAUSA INMEDIATA (si no, el server sigue hasta el final y los
    #     pasos posteriores devuelven ventanas vacías) ------------------------
    pg.evaluate(f"const s=document.getElementById('rp-seek'); s.value={a.seek};"
                "s.dispatchEvent(new Event('input'));"
                "setPaused(true); send({cmd:'pause'});")
    pg.wait_for_timeout(800)
    pg.evaluate(f"""
      const sel=document.getElementById('veh-filter');
      if ([...sel.options].some(o=>o.value==='{a.station}'))
        {{ sel.value='{a.station}'; sel.dispatchEvent(new Event('change')); }}
    """)
    pg.click("#rp-step"); pg.wait_for_timeout(600)
    pg.click("#rp-step"); pg.wait_for_timeout(1000)
    print("eventos congelados:", pg.evaluate("msgEvents.length"))

    # --- escena con zoom sobre el emisor seleccionado ------------------------
    pg.evaluate(f"""
      const v = vehicles.find(x=>String(x.station)==='{a.station}') || vehicles[0];
      if (v) map.jumpTo({{center:[v.lon, v.lat], zoom:{a.zoom}, pitch:55, bearing:-18}});
    """)
    pg.wait_for_timeout(1500)
    pg.evaluate(FORCE)
    pg.screenshot(path=f"{a.out}/replay_paso.png",
                  clip={"x": 420, "y": 40, "width": 1040, "height": 830})

    # --- popup con la disección ASN.1 de un mensaje congelado ----------------
    pg.evaluate("""
      const e = msgEvents.find(x=>x.kind==='tx');
      if (e) { send({cmd:'inspect', station:e.st, t:e.simT, mtype:e.type});
        const pp=document.getElementById('popup');
        pp.style.left='430px'; pp.style.top='50px'; }
    """)
    pg.wait_for_function(
        "document.getElementById('popup').innerText.includes('ITS')",
        timeout=25000)
    pg.wait_for_timeout(300)
    pg.locator("#popup").screenshot(path=f"{a.out}/popup_mensaje.png")
    print("capturas completadas en", a.out)
    b.close()
