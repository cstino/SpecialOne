import unittest

from normalizza import ErroreDataset, normalizza_riga, sql_riga


def riga_valida():
    return {
        "player_id": "252371",
        "fifa_version": "26",
        "short_name": "J. Bellingham",
        "player_positions": "CAM, CM",
        "overall": "90",
        "potential": "94",
        "age": "22",
        "dob": "2003-06-29",
        "height_cm": "186",
        "league_id": "53",
        "club_name": "Real Madrid",
        "nationality_name": "England",
        "preferred_foot": "Right",
        "power_stamina": "94",
        "attacking_finishing": "88",
        "attacking_short_passing": "90",
        "defending_standing_tackle": "79",
        "skill_dribbling": "91",
        "goalkeeping_diving": "14",
        "goalkeeping_handling": "11",
        "goalkeeping_kicking": "10",
        "goalkeeping_positioning": "5",
        "goalkeeping_reflexes": "8",
        "pace": "80",
        "shooting": "86",
        "passing": "83",
        "dribbling": "90",
        "defending": "78",
        "physic": "85",
        "player_face_url": "https://example.invalid/player.png",
    }


class NormalizzazioneTest(unittest.TestCase):
    def test_mappa_riga_fc26(self):
        giocatore = normalizza_riga(riga_valida())
        self.assertEqual(giocatore["campionato"], "La Liga")
        self.assertEqual(giocatore["posizioni"], ["CAM", "CM"])
        self.assertEqual(giocatore["piede"], "destro")
        self.assertEqual(giocatore["attributi"]["gk"], 10)

    def test_rifiuta_campionato_omonimo(self):
        riga = riga_valida()
        riga["league_id"] = "80"  # Bundesliga austriaca
        with self.assertRaises(ErroreDataset):
            normalizza_riga(riga)

    def test_elite_globale_accetta_campionato_esterno_da_75(self):
        riga = riga_valida()
        riga["league_id"] = "39"
        riga["league_name"] = "Major League Soccer"
        riga["overall"] = "75"
        giocatore = normalizza_riga(riga, elite_globale=True)
        self.assertEqual(giocatore["campionato"], "Major League Soccer")
        self.assertTrue(giocatore["elite_globale"])

    def test_rifiuta_ruolo_sconosciuto(self):
        riga = riga_valida()
        riga["player_positions"] = "CAM, XYZ"
        with self.assertRaises(ErroreDataset):
            normalizza_riga(riga)

    def test_lwb_rwb_diventano_esterno_piu_terzino(self):
        riga = riga_valida()
        riga["player_positions"] = "LWB"
        giocatore = normalizza_riga(riga)
        self.assertEqual(giocatore["posizioni"], ["LM", "LB"])

        riga["player_positions"] = "RWB, CM"
        giocatore = normalizza_riga(riga)
        self.assertEqual(giocatore["posizioni"], ["RM", "RB", "CM"])

    def test_lwb_rimpiazzo_non_duplica_ruolo_gia_elencato(self):
        riga = riga_valida()
        riga["player_positions"] = "LWB, LM"
        giocatore = normalizza_riga(riga)
        self.assertEqual(giocatore["posizioni"], ["LM", "LB"])

    def test_upsert_non_azzera_foto_storage(self):
        sql = sql_riga(normalizza_riga(riga_valida()))
        self.assertNotIn("player_face_url", sql)
        self.assertNotIn("example.invalid", sql)


if __name__ == "__main__":
    unittest.main()
