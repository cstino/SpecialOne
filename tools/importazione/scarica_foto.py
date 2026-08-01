#!/usr/bin/env python3
"""Scarica le foto giocatore derivando l'URL da fc_id e prepara WebP 160x160 + SQL.

Variante di prepara_foto.py che non richiede il CSV Kaggle: l'URL del CDN e'
ricostruito dall'fc_id, che e' gia' in `public.players`. Utile quando il dataset
sorgente non e' piu' a portata di mano.

Il sorgente e' la versione 240px, ridimensionata a 160: si ritaglia verso il
basso invece di ingrandire un 120px. La trasparenza del PNG viene mantenuta,
perche' l'interfaccia richiede facce senza rettangolo di sfondo.

L'esecuzione e' ripetibile: i file gia' presenti e non vuoti vengono saltati.
"""

from __future__ import annotations

import argparse
import io
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

CDN = "https://cdn.sofifa.net/players"
UA = "SpecialOne/1.0 (private one-off dataset import)"


def urls_per(fc_id: int) -> list[str]:
    """Il CDN indicizza per id a sei cifre spezzato in due gruppi da tre."""
    chiave = f"{fc_id:06d}"
    gruppo, resto = chiave[:3], chiave[3:6]
    return [
        f"{CDN}/{gruppo}/{resto}/26_240.png",
        f"{CDN}/{gruppo}/{resto}/26_120.png",
    ]


def scarica(url: str, tentativi: int = 3) -> bytes:
    richiesta = urllib.request.Request(url, headers={"User-Agent": UA})
    ultimo_errore: Exception | None = None
    for tentativo in range(tentativi):
        try:
            with urllib.request.urlopen(richiesta, timeout=20) as risposta:
                return risposta.read()
        except Exception as exc:  # la rete puo fallire in molti modi
            ultimo_errore = exc
            if tentativo + 1 < tentativi:
                time.sleep(1.5 * (tentativo + 1))
    assert ultimo_errore is not None
    raise ultimo_errore


def prepara_una(fc_id: int, cartella: Path, qualita: int) -> tuple[int, str | None]:
    from PIL import Image, ImageOps

    destinazione = cartella / f"{fc_id}.webp"
    if destinazione.exists() and destinazione.stat().st_size > 0:
        return fc_id, None

    ultimo_errore: Exception | None = None
    for url in urls_per(fc_id):
        try:
            dati = scarica(url)
            with Image.open(io.BytesIO(dati)) as immagine:
                immagine = ImageOps.fit(
                    immagine.convert("RGBA"), (160, 160), method=Image.Resampling.LANCZOS
                )
                immagine.save(destinazione, "WEBP", quality=qualita, method=6)
            return fc_id, None
        except Exception as exc:
            ultimo_errore = exc
    return fc_id, str(ultimo_errore)


def leggi_ids(percorso: Path) -> list[int]:
    """Accetta l'output JSON di `supabase db query` oppure un id per riga."""
    testo = percorso.read_text(encoding="utf-8")
    inizio = testo.find("{")
    if inizio >= 0:
        try:
            documento = json.loads(testo[inizio:])
            return [int(riga["fc_id"]) for riga in documento["rows"]]
        except (ValueError, KeyError, TypeError):
            pass
    return [int(riga) for riga in testo.split() if riga.strip().isdigit()]


def scrivi_sql(ids: list[int], cartella: Path, dimensione_batch: int = 500) -> None:
    cartella.mkdir(parents=True, exist_ok=True)
    for vecchio in cartella.glob("foto_*.sql"):
        vecchio.unlink()
    for numero, indice in enumerate(range(0, len(ids), dimensione_batch), start=1):
        batch = ids[indice:indice + dimensione_batch]
        valori = ",\n".join(f"({fc_id},'players/{fc_id}.webp')" for fc_id in batch)
        sql = (
            "update public.players as p set foto_url = v.percorso\n"
            f"from (values\n{valori}\n) as v(fc_id, percorso)\n"
            "where p.fc_id = v.fc_id;\n"
        )
        (cartella / f"foto_{numero:04d}.sql").write_text(sql, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ids", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--quality", type=int, default=82)
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()

    try:
        import PIL  # noqa: F401
    except ImportError as exc:
        raise SystemExit(
            "Installa prima tools/importazione/requirements-foto.txt in un virtualenv"
        ) from exc

    ids = leggi_ids(args.ids)
    if args.limit is not None:
        ids = ids[:args.limit]
    cartella_immagini = args.output_dir / "images"
    cartella_immagini.mkdir(parents=True, exist_ok=True)

    riusciti: list[int] = []
    errori: list[tuple[int, str]] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [
            pool.submit(prepara_una, fc_id, cartella_immagini, args.quality)
            for fc_id in ids
        ]
        for completati, future in enumerate(as_completed(futures), start=1):
            fc_id, errore = future.result()
            if errore:
                errori.append((fc_id, errore))
            else:
                riusciti.append(fc_id)
            if completati % 250 == 0 or completati == len(futures):
                print(f"{completati}/{len(futures)} — errori: {len(errori)}", flush=True)

    riusciti.sort()
    scrivi_sql(riusciti, args.output_dir / "sql")
    if errori:
        rapporto = "\n".join(f"{fc_id}\t{errore}" for fc_id, errore in errori) + "\n"
        (args.output_dir / "errori-foto.tsv").write_text(rapporto, encoding="utf-8")
    print(f"Foto pronte: {len(riusciti)}; errori: {len(errori)}")


if __name__ == "__main__":
    main()
