#!/usr/bin/env python3
"""Prepara un suono di sottofondo perche' si ripeta senza stacco.

Uso: python3 tools/suoni/prepara-loop.py ingresso.m4a uscita.m4a [secondi di dissolvenza]

Il file in uscita entra in dissolvenza all'inizio ed esce in dissolvenza alla
fine (curve a potenza costante). Il gioco lo suona con due lettori sfasati
(src/lib/sottofondoStadio.ts): il secondo parte quando al primo manca proprio
quella dissolvenza, e la somma dei due resta a volume costante. Non serve
toccare il volume dei lettori, che sull'iPhone non si puo' cambiare.
Usa afconvert (macOS) per leggere e scrivere l'AAC, e numpy per i conti.
"""
import struct, subprocess, sys, tempfile, wave, os
import numpy as np

ingresso, uscita = sys.argv[1], sys.argv[2]
dissolvenza = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0

with tempfile.TemporaryDirectory() as d:
    grezzo, pronto = os.path.join(d, 'a.wav'), os.path.join(d, 'b.wav')
    subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@44100', ingresso, grezzo], check=True)
    dati = open(grezzo, 'rb').read()
    # afconvert scrive un WAV "esteso" che il modulo wave non legge: i blocchi si cercano a mano.
    p, canali, hz, campioni = 12, 2, 44100, None
    while p < len(dati) - 8:
        nome, lung = dati[p:p + 4], struct.unpack('<I', dati[p + 4:p + 8])[0]
        if nome == b'fmt ': canali, hz = struct.unpack('<HI', dati[p + 10:p + 16])
        if nome == b'data': campioni = np.frombuffer(dati[p + 8:p + 8 + lung], dtype='<i2'); break
        p += 8 + lung + (lung & 1)
    x = campioni.reshape(-1, canali).astype(np.float64)

    # Via il silenzio in testa e in coda (registrazioni tagliate male).
    forte = np.flatnonzero(np.abs(x).max(axis=1) > 200)
    x = x[forte[0]:forte[-1] + 1]
    n = int(dissolvenza * hz)
    t = np.linspace(0, np.pi / 2, n)[:, None]
    x[:n] *= np.sin(t)
    x[-n:] *= np.cos(t)

    with wave.open(pronto, 'wb') as w:
        w.setnchannels(canali); w.setsampwidth(2); w.setframerate(hz)
        w.writeframes(np.clip(np.round(x), -32768, 32767).astype('<i2').tobytes())
    subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', '128000', pronto, uscita], check=True)

    def rms(a): return float(np.sqrt((a ** 2).mean()))
    centro = rms(x[n:-n])
    # Come suonera' il passaggio: coda del primo lettore sommata alla testa del secondo.
    giunto = x[-n:] + x[:n]
    print(f'durata {len(x) / hz:.2f} s, ciclo {len(x) / hz - dissolvenza:.2f} s')
    print(f'volume medio {centro:.0f}, sul passaggio {rms(giunto):.0f} ({100 * rms(giunto) / centro:.0f}% del medio)')
