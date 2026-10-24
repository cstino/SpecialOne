import itertools
from math import comb
from modello_slot import *

CAP = 500

# ---- Scegli lo stemma: 9 scudi, se ne scelgono 3, si vince la somma (tetto 500x) ----
STEMMA_V = [1, 2, 3, 5, 10, 25, 100, 250]
def ev_stemma(w, picks=3):
    tot = sum(w); p = [x/tot for x in w]
    dist = {0: 1.0}
    for _ in range(picks):
        nd = {}
        for s, ps in dist.items():
            for v, pv in zip(STEMMA_V, p):
                nd[s+v] = nd.get(s+v, 0) + ps*pv
        dist = nd
    ev = sum(min(s, CAP)*pr for s, pr in dist.items())
    p100 = sum(pr for s, pr in dist.items() if s >= 100)
    pmax = sum(pr for s, pr in dist.items() if s >= 300)
    return ev, p100, pmax, dist

# ---- Calcio di rigore: 5 tiri, il primo para chiude; premio in base ai gol ----
def ev_rigori(pg, lad):
    ev = 0.0; surv = 1.0; dist = []
    for k in range(6):
        if k < 5:
            pk = surv * (1 - pg[k]); surv *= pg[k]
        else:
            pk = surv
        dist.append((k, pk, lad[k])); ev += pk * lad[k]
    return ev, dist

if __name__ == '__main__':
    w = [30, 28, 18, 12, 7, 3.5, 1.2, 0.3]
    print('stemma', [round(x, 4) for x in ev_stemma(w)[:3]])
    pg = [0.80, 0.72, 0.64, 0.55, 0.45]
    for lad in ([1, 2, 4, 10, 30, 200], [0.5, 1, 2, 5, 20, 150], [0, 1, 2, 5, 20, 150]):
        ev, dist = ev_rigori(pg, lad); print('rigori', lad, round(ev, 3))
