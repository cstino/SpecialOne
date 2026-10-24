import itertools, math
from math import comb

PAGA = {  # album: (basso, medio, alto) per n=3,4,5 (in decimi di puntata)
    'alb': {'b': (9,29,110), 'm': (16,56,222), 'a': (29,136,550)},
    'base': {'b': (8,26,100), 'm': (14,52,200), 'a': (26,125,500)},
}
def classe(s): return 'b' if s <= 2 else 'm' if s <= 5 else 'a'

def linea_attesa(p, paga, jolly=8):
    """valore atteso (in decimi di puntata, senza scala) di UNA linea; p = probabilita' per simbolo (indice = simbolo)."""
    ns = len(p); tot = 0.0
    for seq in itertools.product(range(ns), repeat=5):
        pr = 1.0
        for s in seq: pr *= p[s]
        if pr == 0: continue
        target = None; n = 0
        for s in seq:
            if s >= 9: break
            if target is None and s != jolly: target = s
            if s == jolly or s == target: n += 1
            else: break
        v = 0
        if target is None and n == 5: v = 400
        elif n >= 3 and target is not None: v = paga[classe(target)][n-3]
        tot += pr * v
    return tot

def binom_pmf(n, k, q): return comb(n, k) * q**k * (1-q)**(n-k)

def rtp(pesi, paga, scala, bonus_ev=0.0, p_bonus=0.0, scatter=((3,2,8),(4,5,12),(5,20,20))):
    T = sum(pesi); p = [w/T for w in pesi]
    el10 = 10 * linea_attesa(p, paga) / 10.0 * scala        # coefficiente di puntata, 10 linee
    es = 0.0; nuovi = 0.0
    for k in range(3, 16):
        pk = binom_pmf(15, k, p[9]); kk = min(k, 5)
        mult, gratis = next((m, g) for (kx, m, g) in scatter if kx == kk)
        es += pk * mult * scala; nuovi += pk * gratis
    w = el10 + es
    catena = 2 * w / (1 - nuovi)                              # valore di un giro gratis con tutti i suoi rilanci
    spin_tot = 1 / (1 - nuovi)                                # giri totali (pagati + gratis) per giro pagato
    tot = w + nuovi * (catena + 0)                            # senza bonus
    bonus = p_bonus * bonus_ev * spin_tot                     # i bonus scattano anche nei giri gratis
    return dict(rtp=tot + bonus, linee=el10, scatter=es, nuovi=nuovi, spin_tot=spin_tot, bonus=bonus, w=w)

if __name__ == '__main__':
    pesi_alb = [90,90,90,70,70,70,40,40,30,20,22]
    r = rtp(pesi_alb, PAGA['alb'], 1.033)
    print('album  :', {k: round(v,4) for k,v in r.items()})
    pesi_base = [90,90,90,70,70,70,40,40,30,20,0]
    r = rtp(pesi_base, PAGA['base'], 1.024)
    print('base   :', {k: round(v,4) for k,v in r.items()})
