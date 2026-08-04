#!/usr/bin/env python3
"""Normalizza il CSV FC 26 e genera batch SQL ripetibili per `players`."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Iterable, Iterator


SOURCE_URL = "https://www.kaggle.com/datasets/rovnez/fc-26-fifa-26-player-data"
SOURCE_LICENSE = "CC BY 4.0"
SOURCE_SNAPSHOT = "2025-09-21"

# Gli id evitano collisioni di nome (es. Bundesliga tedesca/austriaca,
# Serie A italiana/ecuadoriana, Premier League inglese/ucraina).
CAMPIONATI_BASE = {
    "13": "Premier League",
    "53": "La Liga",
    "31": "Serie A",
    "19": "Bundesliga",
    "16": "Ligue 1",
    "10": "Eredivisie",
    "308": "Liga Portugal",
    "68": "Süper Lig",
    "350": "Saudi Pro League",
    "14": "EFL Championship",
}

RUOLI_VALIDI = {
    "GK", "CB", "LB", "RB", "LWB", "RWB",
    "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST", "CF",
}

COLONNE_OBBLIGATORIE = {
    "player_id", "fifa_version", "short_name", "player_positions",
    "overall", "potential", "age", "dob", "height_cm", "league_id",
    "club_name", "nationality_name", "preferred_foot",
    "power_stamina", "attacking_finishing", "attacking_short_passing",
    "defending_standing_tackle", "skill_dribbling", "goalkeeping_diving",
    "goalkeeping_handling", "goalkeeping_kicking", "goalkeeping_positioning",
    "goalkeeping_reflexes", "pace", "shooting", "passing", "dribbling",
    "defending", "physic", "player_face_url",
}

CAMPI_ATTRIBUTI = {
    "pace": "pace",
    "shooting": "shooting",
    "passing": "passing",
    "dribbling_generale": "dribbling",
    "defending": "defending",
    "physic": "physic",
    "stamina": "power_stamina",
    "finishing": "attacking_finishing",
    "short_passing": "attacking_short_passing",
    "standing_tackle": "defending_standing_tackle",
    "dribbling": "skill_dribbling",
    "gk_diving": "goalkeeping_diving",
    "gk_handling": "goalkeeping_handling",
    "gk_kicking": "goalkeeping_kicking",
    "gk_positioning": "goalkeeping_positioning",
    "gk_reflexes": "goalkeeping_reflexes",
}


class ErroreDataset(ValueError):
    pass


def intero(riga: dict[str, str], campo: str, minimo: int, massimo: int) -> int:
    valore = riga.get(campo, "").strip()
    if not valore:
        raise ErroreDataset(f"player_id={riga.get('player_id')}: manca {campo}")
    try:
        numero = int(float(valore))
    except ValueError as exc:
        raise ErroreDataset(
            f"player_id={riga.get('player_id')}: {campo} non numerico ({valore!r})"
        ) from exc
    if not minimo <= numero <= massimo:
        raise ErroreDataset(
            f"player_id={riga.get('player_id')}: {campo}={numero} fuori range"
        )
    return numero


def intero_opzionale(riga: dict[str, str], campo: str) -> int | None:
    valore = riga.get(campo, "").strip()
    return int(float(valore)) if valore else None


def normalizza_ruoli(riga: dict[str, str]) -> list[str]:
    ruoli = [ruolo.strip().upper() for ruolo in riga["player_positions"].split(",")]
    if not 1 <= len(ruoli) <= 6 or len(set(ruoli)) != len(ruoli):
        raise ErroreDataset(f"player_id={riga['player_id']}: ruoli non validi {ruoli}")
    sconosciuti = set(ruoli) - RUOLI_VALIDI
    if sconosciuti:
        raise ErroreDataset(
            f"player_id={riga['player_id']}: ruoli sconosciuti {sorted(sconosciuti)}"
        )
    return ruoli


def normalizza_riga(riga: dict[str, str], elite_globale: bool = False) -> dict[str, object]:
    if elite_globale:
        campionato = riga.get("league_name", "").strip()
        if not campionato:
            raise ErroreDataset(f"player_id={riga['player_id']}: campionato esterno mancante")
    elif riga["league_id"] in CAMPIONATI_BASE:
        campionato = CAMPIONATI_BASE[riga["league_id"]]
    else:
        raise ErroreDataset(f"Campionato non selezionato: {riga['league_id']}")
    if riga["fifa_version"].strip() != "26":
        raise ErroreDataset(f"player_id={riga['player_id']}: snapshot non FC 26")

    piede = {"Right": "destro", "Left": "sinistro"}.get(riga["preferred_foot"].strip())
    if piede is None:
        raise ErroreDataset(
            f"player_id={riga['player_id']}: piede sconosciuto {riga['preferred_foot']!r}"
        )

    overall = intero(riga, "overall", 40, 99)
    potential = intero(riga, "potential", 40, 99)
    if potential < overall:
        raise ErroreDataset(f"player_id={riga['player_id']}: potential sotto overall")

    attributi = {
        nome: intero_opzionale(riga, colonna)
        for nome, colonna in CAMPI_ATTRIBUTI.items()
    }
    valori_gk = [
        attributi["gk_diving"],
        attributi["gk_handling"],
        attributi["gk_kicking"],
        attributi["gk_positioning"],
        attributi["gk_reflexes"],
    ]
    if any(valore is None for valore in valori_gk):
        raise ErroreDataset(f"player_id={riga['player_id']}: attributi portiere incompleti")
    attributi["gk"] = round(sum(valori_gk) / len(valori_gk))  # type: ignore[arg-type]

    for richiesto in ("stamina", "finishing", "short_passing", "standing_tackle", "dribbling"):
        if attributi[richiesto] is None:
            raise ErroreDataset(f"player_id={riga['player_id']}: manca {richiesto}")

    nome = riga["short_name"].strip()
    club = riga["club_name"].strip()
    if not nome or not club:
        raise ErroreDataset(f"player_id={riga['player_id']}: nome o club mancante")

    return {
        "fc_id": intero(riga, "player_id", 1, 2**63 - 1),
        "nome": nome,
        "nazionalita": riga["nationality_name"].strip() or None,
        "club": club,
        "campionato": campionato,
        "elite_globale": elite_globale,
        "overall": overall,
        "potential": potential,
        "eta": intero(riga, "age", 15, 45),
        "data_nascita": riga["dob"].strip() or None,
        "posizioni": normalizza_ruoli(riga),
        "piede": piede,
        "altezza": intero(riga, "height_cm", 140, 220),
        "attributi": attributi,
    }


def righe_selezionate(percorso: Path, elite_globale: bool = False) -> Iterator[dict[str, str]]:
    with percorso.open(encoding="utf-8-sig", newline="") as file_csv:
        lettore = csv.DictReader(file_csv)
        mancanti = COLONNE_OBBLIGATORIE - set(lettore.fieldnames or [])
        if mancanti:
            raise ErroreDataset(f"Colonne mancanti: {sorted(mancanti)}")
        for riga in lettore:
            if not elite_globale and riga["league_id"] in CAMPIONATI_BASE:
                yield riga
            elif (
                elite_globale
                and riga["league_id"] not in CAMPIONATI_BASE
                and riga.get("league_name", "").strip()
                and int(float(riga["overall"])) >= 75
            ):
                yield riga


def leggi_giocatori(percorso: Path, elite_globale: bool = False) -> list[dict[str, object]]:
    giocatori = [normalizza_riga(riga, elite_globale) for riga in righe_selezionate(percorso, elite_globale)]
    ids = [giocatore["fc_id"] for giocatore in giocatori]
    if len(ids) != len(set(ids)):
        duplicati = [fc_id for fc_id, n in Counter(ids).items() if n > 1]
        raise ErroreDataset(f"fc_id duplicati: {duplicati[:10]}")
    if elite_globale:
        if not 1 <= len(giocatori) <= 1000:
            raise ErroreDataset(f"Volume elite inatteso: {len(giocatori)} giocatori")
        return giocatori
    if not 5000 <= len(giocatori) <= 6500:
        raise ErroreDataset(f"Volume inatteso: {len(giocatori)} giocatori")
    presenti = {giocatore["campionato"] for giocatore in giocatori}
    attesi = set(CAMPIONATI_BASE.values())
    if presenti != attesi:
        raise ErroreDataset(f"Campionati mancanti: {sorted(attesi - presenti)}")
    return giocatori


def sql_testo(valore: object | None) -> str:
    if valore is None:
        return "null"
    return "'" + str(valore).replace("'", "''") + "'"


def sql_array(valori: Iterable[str]) -> str:
    return "array[" + ",".join(sql_testo(valore) for valore in valori) + "]::text[]"


def sql_riga(giocatore: dict[str, object]) -> str:
    attributi = json.dumps(
        giocatore["attributi"], ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    return "(" + ",".join([
        str(giocatore["fc_id"]),
        sql_testo(giocatore["nome"]),
        sql_testo(giocatore["nazionalita"]),
        sql_testo(giocatore["club"]),
        sql_testo(giocatore["campionato"]),
        "true" if giocatore["elite_globale"] else "false",
        str(giocatore["overall"]),
        str(giocatore["potential"]),
        str(giocatore["eta"]),
        sql_testo(giocatore["data_nascita"]),
        sql_array(giocatore["posizioni"]),  # type: ignore[arg-type]
        sql_testo(giocatore["piede"]),
        str(giocatore["altezza"]),
        sql_testo(attributi) + "::jsonb",
    ]) + ")"


def scrivi_batch(
    giocatori: list[dict[str, object]], cartella: Path, dimensione_batch: int
) -> int:
    cartella.mkdir(parents=True, exist_ok=True)
    for vecchio in cartella.glob("players_*.sql"):
        vecchio.unlink()

    colonne = (
        "fc_id,nome,nazionalita,club,campionato,elite_globale,overall,potential,eta,"
        "data_nascita,posizioni,piede,altezza,attributi"
    )
    aggiornamenti = (
        "nome=excluded.nome,nazionalita=excluded.nazionalita,club=excluded.club,"
        "campionato=excluded.campionato,elite_globale=excluded.elite_globale,overall=excluded.overall,"
        "potential=excluded.potential,eta=excluded.eta,"
        "data_nascita=excluded.data_nascita,posizioni=excluded.posizioni,"
        "piede=excluded.piede,altezza=excluded.altezza,attributi=excluded.attributi"
    )

    numero_batch = 0
    for indice in range(0, len(giocatori), dimensione_batch):
        numero_batch += 1
        righe = giocatori[indice:indice + dimensione_batch]
        sql = (
            "begin;\n"
            f"insert into public.players ({colonne}) values\n"
            + ",\n".join(sql_riga(giocatore) for giocatore in righe)
            + f"\non conflict (fc_id) do update set {aggiornamenti};\n"
            "commit;\n"
        )
        (cartella / f"players_{numero_batch:04d}.sql").write_text(sql, encoding="utf-8")
    return numero_batch


def sha256(percorso: Path) -> str:
    digest = hashlib.sha256()
    with percorso.open("rb") as file_binario:
        for blocco in iter(lambda: file_binario.read(1024 * 1024), b""):
            digest.update(blocco)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=250)
    parser.add_argument("--elite-globale", action="store_true",
                        help="Importa solo giocatori OVR 75+ dai campionati non inclusi nel pool base.")
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 1000:
        parser.error("--batch-size deve essere tra 1 e 1000")

    giocatori = leggi_giocatori(args.input, args.elite_globale)
    numero_batch = scrivi_batch(giocatori, args.output_dir, args.batch_size)
    conteggi = Counter(str(g["campionato"]) for g in giocatori)
    manifest = {
        "source": SOURCE_URL,
        "license": SOURCE_LICENSE,
        "snapshot": SOURCE_SNAPSHOT,
        "input_sha256": sha256(args.input),
        "players": len(giocatori),
        "clubs": len({str(g["club"]) for g in giocatori}),
        "leagues": dict(sorted(conteggi.items())),
        "batches": numero_batch,
        "elite_globale": args.elite_globale,
    }
    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
