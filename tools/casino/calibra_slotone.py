"""Taratura di SlotOne con i minigiochi (24/10/2026): trova il peso dei due simboli nuovi (pallone e stemma d'oro) e la
scala dei pagamenti che riportano il ritorno al 97% in crediti. Uso: python3 tools/casino/calibra_slotone.py
Poi si controlla con la simulazione: docker exec -i supabase-db psql -U postgres -At < tools/casino/simula_slotone.sql
(modificando pesi e scala nell'ultima riga)."""
from math import comb
from modello_slot import rtp, PAGA
from bonus_modello import ev_stemma, ev_rigori

VALORI_STEMMA_PESI = [38, 30, 15, 8, 5, 3, 0.8, 0.15]           # valori 1,2,3,5,10,25,100,250
RIGORI_P_GOL = [0.78, 0.68, 0.58, 0.48, 0.38]
RIGORI_SCALA = [1, 2, 4, 8, 25, 120]                              # premio per 0..5 gol
TARGET_RTP = 0.97
FREQUENZA_PER_BONUS = 0.005                                       # un minigioco ogni 200 giri, ciascuno

def p_scatta(w, tot):
    q = w / tot
    return sum(comb(15, k) * q**k * (1 - q)**(15 - k) for k in range(3, 16))

def calibra(pesi_base, paga):
    lo, hi = 50.0, 400.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if p_scatta(mid, sum(pesi_base) + 2 * mid) > FREQUENZA_PER_BONUS: hi = mid
        else: lo = mid
    w = round(lo); tot = sum(pesi_base) + 2 * w; pt = p_scatta(w, tot)
    ev = ev_stemma(VALORI_STEMMA_PESI)[0] + ev_rigori(RIGORI_P_GOL, RIGORI_SCALA)[0]
    lo, hi = 0.5, 1.3
    for _ in range(60):
        mid = (lo + hi) / 2
        if rtp(pesi_base + [w, w], paga, mid, bonus_ev=ev, p_bonus=pt)['rtp'] > TARGET_RTP: hi = mid
        else: lo = mid
    return w, pt, lo, rtp(pesi_base + [w, w], paga, lo, bonus_ev=ev, p_bonus=pt)

if __name__ == '__main__':
    for nome, pesi, paga in (('con album', [900,900,900,700,700,700,400,400,300,200,220], PAGA['alb']),
                             ('senza album', [900,900,900,700,700,700,400,400,300,200,0], PAGA['base'])):
        w, pt, scala, r = calibra(pesi, paga)
        print(f'{nome}: peso nuovi simboli {w}, P(scatta)={pt:.5f}, scala {scala:.4f}, ritorno {r["rtp"]:.4f} '
              f'(linee {r["linee"]:.3f}, scatter {r["scatter"]:.3f}, bonus {r["bonus"]:.3f})')
