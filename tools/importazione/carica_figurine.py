#!/usr/bin/env python3
"""Carica nel bucket player-photos le foto scontornate preparate da scarica_figurine.py.

I file vanno in cutout/<id>.webp; poi si scrive un SQL che riempie players.foto_figurina, da
applicare con docker exec ... psql come ogni migrazione dati. La chiave di servizio si legge dal
.env del server sul Mac e non viene mai stampata.

Uso:
  python3 tools/importazione/carica_figurine.py --output-dir /tmp/figurine \
    --env ~/supabase-spinoff/project/.env --sql /tmp/figurine/foto_figurina.sql
"""

from __future__ import annotations

import argparse
import json
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def leggi_env(percorso: Path) -> dict[str, str]:
    valori = {}
    for riga in percorso.expanduser().read_text().splitlines():
        if "=" in riga and not riga.lstrip().startswith("#"):
            chiave, valore = riga.split("=", 1)
            valori[chiave.strip()] = valore.strip().strip('"').strip("'")
    return valori


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--env", type=Path, required=True)
    parser.add_argument("--sql", type=Path, required=True)
    parser.add_argument("--url", help="indirizzo dell'API (predefinito: SUPABASE_PUBLIC_URL del .env)")
    args = parser.parse_args()

    env = leggi_env(args.env)
    base = (args.url or env["SUPABASE_PUBLIC_URL"]).rstrip("/")
    chiave = env["SERVICE_ROLE_KEY"]
    esiti = json.loads((args.output_dir / "esiti.json").read_text())
    ids = [pid for pid, e in esiti.items() if e["esito"] == "ok" and (args.output_dir / "cutout" / f"{pid}.webp").exists()]

    def carica(pid: str) -> tuple[str, str | None]:
        dati = (args.output_dir / "cutout" / f"{pid}.webp").read_bytes()
        richiesta = urllib.request.Request(
            f"{base}/storage/v1/object/player-photos/cutout/{pid}.webp", data=dati, method="POST",
            headers={"Authorization": f"Bearer {chiave}", "apikey": chiave, "Content-Type": "image/webp",
                     "x-upsert": "true", "Cache-Control": "max-age=31536000"},
        )
        try:
            with urllib.request.urlopen(richiesta, timeout=60):
                return pid, None
        except Exception as exc:
            return pid, str(exc)

    riusciti, errori = [], []
    with ThreadPoolExecutor(max_workers=6) as pool:
        for pid, errore in pool.map(carica, ids):
            (errori if errore else riusciti).append((pid, errore))
    print(f"caricate {len(riusciti)} · errori {len(errori)}", flush=True)
    for pid, errore in errori[:10]:
        print("  ", pid, errore)

    valori = ",\n".join(f"({pid}, 'cutout/{pid}.webp')" for pid, _ in riusciti)
    args.sql.write_text(
        "-- Foto scontornate delle figurine (tools/importazione/carica_figurine.py)\n"
        "update public.players p set foto_figurina = v.percorso\n"
        f"from (values\n{valori}\n) as v(id, percorso)\nwhere p.id = v.id;\n" if riusciti else "select 1;\n"
    )


if __name__ == "__main__":
    main()
