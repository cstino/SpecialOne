#!/usr/bin/env python3
"""Scarica le foto scontornate (stile card FUT) dei giocatori reali da TheSportsDB.

Servono solo alle figurine dell'album (Season 3, docs/DIARIO-SEASON3.md §9): le foto di sempre
(players.foto_url, ritratti EA 160x160) restano dove sono per il resto dell'app.

Ingresso: un TSV con id, nome, nome_completo, nazionalita, data_nascita (una riga per giocatore,
nell'ordine in cui scaricarli). Uscita: <output>/cutout/<id>.webp (360 px di lato, trasparenza
mantenuta, con cwebp) e <output>/esiti.json con l'esito di ogni giocatore.

Una foto si accetta solo se TheSportsDB ha la stessa data di nascita: con due omonimi si rischierebbe
la faccia sbagliata. TheSportsDB limita le richieste (circa una ogni 2 secondi con la chiave gratuita):
lo script rallenta da solo quando riceve 429 ed e' ripetibile, i giocatori gia' esaminati si saltano.

Con l'abbonamento a TheSportsDB la chiave sta nel .env del server (THESPORTSDB_KEY=...): con --env la si legge da
li' senza stamparla, e le richieste vanno al ritmo concesso (--pausa 0.7, circa 85 al minuto).

Uso:
  python3 tools/importazione/scarica_figurine.py --giocatori giocatori.tsv --output-dir /tmp/figurine
  python3 tools/importazione/scarica_figurine.py --giocatori giocatori.tsv --output-dir /tmp/figurine \
    --env ~/supabase-spinoff/project/.env --pausa 0.7
"""

from __future__ import annotations

import argparse
import json
import subprocess
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://www.thesportsdb.com/api/v1/json/{chiave}/searchplayers.php?p="
CHIAVE = "123"
PAUSA = 2.1
UA = "SpecialOne/1.0 (private one-off dataset import)"


def norm(testo: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", testo.lower()) if unicodedata.category(c) != "Mn")


def ricerche(nome: str, completo: str) -> list[str]:
    """'M. Salah' + 'Mohamed Salah Hamed Ghaly' -> 'Mohamed Salah', poi gli altri tentativi."""
    tentativi = []
    parti = nome.split(" ")
    if parti[0].endswith(".") and completo and len(parti) > 1:
        tentativi.append(completo.split(" ")[0] + " " + " ".join(parti[1:]))
    else:
        tentativi.append(nome)
    if completo and completo not in tentativi:
        tentativi.append(completo)
    parole = completo.split(" ") if completo else []
    if len(parole) > 2:
        tentativi.append(parole[0] + " " + parole[-1])
    return list(dict.fromkeys(tentativi))


def chiedi(url: str) -> bytes:
    attesa = 20
    for _ in range(12):
        try:
            richiesta = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(richiesta, timeout=30) as risposta:
                return risposta.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise
            time.sleep(attesa)
            attesa = min(attesa * 2, 300)
        except Exception:
            time.sleep(attesa)
            attesa = min(attesa * 2, 300)
    raise RuntimeError("troppi tentativi: " + url)


def trova(nome: str, completo: str, nascita: str) -> tuple[dict | None, str]:
    for q in ricerche(nome, completo):
        dati = json.loads(chiedi(API.format(chiave=CHIAVE) + urllib.parse.quote(q)) or b"{}")
        time.sleep(PAUSA)
        for p in dati.get("player") or []:
            if p.get("strSport") != "Soccer":
                continue
            if nascita and p.get("dateBorn") == nascita:
                return p, q
    return None, ""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--giocatori", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--lato", type=int, default=360)
    parser.add_argument("--env", type=Path, help="file .env con THESPORTSDB_KEY (la chiave non viene mai stampata)")
    parser.add_argument("--pausa", type=float, default=2.1, help="secondi fra una ricerca e l'altra")
    args = parser.parse_args()

    global CHIAVE, PAUSA
    PAUSA = args.pausa
    if args.env:
        for riga in args.env.expanduser().read_text().splitlines():
            if riga.startswith("THESPORTSDB_KEY="):
                CHIAVE = riga.split("=", 1)[1].strip().strip('"').strip("'")
        if CHIAVE == "123":
            raise SystemExit("THESPORTSDB_KEY non trovata nel file .env")

    cartella = args.output_dir / "cutout"
    cartella.mkdir(parents=True, exist_ok=True)
    file_esiti = args.output_dir / "esiti.json"
    esiti: dict[str, dict] = json.loads(file_esiti.read_text()) if file_esiti.exists() else {}

    righe = [r.rstrip("\n").split("\t") for r in args.giocatori.read_text(encoding="utf-8").splitlines() if r.strip()]
    for numero, (pid, nome, completo, _naz, nascita, *_resto) in enumerate(righe, start=1):
        if pid in esiti:
            continue
        try:
            trovato, q = trova(nome, completo, nascita)
            if not trovato:
                esiti[pid] = {"esito": "non_trovato"}
            elif not trovato.get("strCutout"):
                esiti[pid] = {"esito": "senza_foto", "nome": trovato.get("strPlayer")}
            else:
                png = args.output_dir / "tmp.png"
                png.write_bytes(chiedi(trovato["strCutout"]))
                subprocess.run(
                    ["cwebp", "-quiet", "-q", "80", "-alpha_q", "90", "-resize", str(args.lato), "0", str(png), "-o", str(cartella / f"{pid}.webp")],
                    check=True,
                )
                esiti[pid] = {"esito": "ok", "nome": trovato.get("strPlayer"), "ricerca": q, "squadra": trovato.get("strTeam")}
        except Exception as exc:  # un giocatore non deve fermare gli altri: si riprova al prossimo giro
            print(f"errore {pid} {nome}: {exc}", flush=True)
            continue
        if numero % 25 == 0 or numero == len(righe):
            file_esiti.write_text(json.dumps(esiti, ensure_ascii=False))
            ok = sum(1 for e in esiti.values() if e["esito"] == "ok")
            print(f"{numero}/{len(righe)} esaminati · {ok} foto", flush=True)
    file_esiti.write_text(json.dumps(esiti, ensure_ascii=False))


if __name__ == "__main__":
    main()
