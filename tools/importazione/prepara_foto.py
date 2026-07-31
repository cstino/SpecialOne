#!/usr/bin/env python3
"""Scarica le foto sorgente e prepara WebP 160x160 + SQL dei percorsi Storage."""

from __future__ import annotations

import argparse
import io
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from normalizza import normalizza_riga, righe_selezionate, sql_testo


def scarica(url: str, tentativi: int = 3) -> bytes:
    richiesta = urllib.request.Request(
        url,
        headers={"User-Agent": "SpecialOne/1.0 (private one-off dataset import)"},
    )
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


def prepara_una(riga: dict[str, str], cartella: Path, qualita: int) -> tuple[int, str | None]:
    from PIL import Image, ImageOps

    giocatore = normalizza_riga(riga)
    fc_id = int(giocatore["fc_id"])
    destinazione = cartella / f"{fc_id}.webp"
    if destinazione.exists() and destinazione.stat().st_size > 0:
        return fc_id, None
    try:
        dati = scarica(riga["player_face_url"])
        with Image.open(io.BytesIO(dati)) as immagine:
            immagine = ImageOps.fit(
                immagine.convert("RGBA"), (160, 160), method=Image.Resampling.LANCZOS
            )
            immagine.save(destinazione, "WEBP", quality=qualita, method=6)
        return fc_id, None
    except Exception as exc:
        return fc_id, str(exc)


def scrivi_sql(ids: list[int], cartella: Path, dimensione_batch: int = 500) -> None:
    cartella.mkdir(parents=True, exist_ok=True)
    for vecchio in cartella.glob("foto_*.sql"):
        vecchio.unlink()
    for numero, indice in enumerate(range(0, len(ids), dimensione_batch), start=1):
        batch = ids[indice:indice + dimensione_batch]
        valori = ",\n".join(
            f"({fc_id},{sql_testo(f'players/{fc_id}.webp')})" for fc_id in batch
        )
        sql = (
            "update public.players as p set foto_url = v.percorso\n"
            f"from (values\n{valori}\n) as v(fc_id, percorso)\n"
            "where p.fc_id = v.fc_id;\n"
        )
        (cartella / f"foto_{numero:04d}.sql").write_text(sql, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
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

    righe = list(righe_selezionate(args.input))
    if args.limit is not None:
        righe = righe[:args.limit]
    cartella_immagini = args.output_dir / "images"
    cartella_sql = args.output_dir / "sql"
    cartella_immagini.mkdir(parents=True, exist_ok=True)

    riusciti: list[int] = []
    errori: list[tuple[int, str]] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [
            pool.submit(prepara_una, riga, cartella_immagini, args.quality)
            for riga in righe
        ]
        for completati, future in enumerate(as_completed(futures), start=1):
            fc_id, errore = future.result()
            if errore:
                errori.append((fc_id, errore))
            else:
                riusciti.append(fc_id)
            if completati % 250 == 0 or completati == len(futures):
                print(f"{completati}/{len(futures)} — errori: {len(errori)}")

    riusciti.sort()
    scrivi_sql(riusciti, cartella_sql)
    if errori:
        rapporto = "\n".join(f"{fc_id}\t{errore}" for fc_id, errore in errori) + "\n"
        (args.output_dir / "errori-foto.tsv").write_text(rapporto, encoding="utf-8")
    print(f"Foto pronte: {len(riusciti)}; errori: {len(errori)}")
    if errori:
        raise SystemExit("Download incompleto: correggi gli errori e rilancia prima dell'upload")


if __name__ == "__main__":
    main()
