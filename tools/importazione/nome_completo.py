#!/usr/bin/env python3
"""Riempie public.players.nome_completo dal campo long_name del dataset FC 26.

Uso (una tantum, dopo aver scaricato il CSV come da README):

  python3 tools/importazione/nome_completo.py \\
      --csv /tmp/fc26-player-data/FC26_20250921.csv \\
      --giocatori giocatori.json > nome_completo.sql

`giocatori.json` e' l'esito di `select id, fc_id, nome from public.players` in JSON
(`supabase db query ... -o json`). Si applica poi con `supabase db query --file`.
Il long_name del dataset a volte porta in coda lo stesso nome in cirillico o in altri
alfabeti ("Kosta NedeljkovicКоста Недељковић"): si taglia al primo carattere non
latino. Se il nome ripulito coincide col nome breve non si scrive niente.
"""
import argparse
import csv
import json
import re
import sys

LATINO = re.compile(r"^[\u0000-ɏḀ-ỿ’]+")


def ripulisci(nome: str) -> str:
    tagliato = LATINO.match(nome or "")
    return re.sub(r"\s+", " ", (tagliato.group(0) if tagliato else "")).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True)
    parser.add_argument("--giocatori", required=True)
    args = parser.parse_args()

    righe = json.load(open(args.giocatori))
    righe = righe["rows"] if isinstance(righe, dict) else righe
    lunghi = {}
    with open(args.csv, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            lunghi[r["player_id"]] = r["long_name"]

    valori = []
    for g in righe:
        lungo = ripulisci(lunghi.get(str(g["fc_id"]), ""))
        if not lungo or lungo.lower() == (g["nome"] or "").strip().lower():
            continue
        valori.append((g["id"], lungo))

    print("begin;")
    for i in range(0, len(valori), 500):
        blocco = ",\n".join("(%d, '%s')" % (pid, n.replace("'", "''")) for pid, n in valori[i:i + 500])
        print("update public.players p set nome_completo = v.n from (values\n%s\n) as v(id, n) where p.id = v.id;" % blocco)
    print("commit;")
    print("-- %d nomi completi" % len(valori), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
