# Originali degli asset — NON vengono pubblicati

Questa cartella sta **fuori da `public/`** apposta.

Vite copia tutto il contenuto di `public/` dentro `dist/` alla lettera, senza
guardare se qualcosa lo referenzia. Gli stemmi a piena risoluzione (1254x1254,
16 MB in 42 file) stavano lì ma nessuno li usava: l'app carica solo
`public/stemmi-squadra/thumbs/` a 320x320, che bastano perché uno stemma si
vede a 42-46 px e al massimo a 118 nel selettore.

Risultato: ogni deploy su Vercel si portava dietro 16 MB di file che nessun
browser avrebbe mai chiesto. Con decine di deploy conservati, è così che si è
riempito lo spazio del piano gratuito.

**Servono ancora**: sono i master da cui si rigenerano i thumb se un domani
serviranno più grandi o in un altro formato. Non vanno cancellati — vanno solo
tenuti fuori da `public/`.

Per rigenerare un thumb da un originale:

    sips -Z 320 assets-originali/stemmi-squadra/NOME.png \
         --out public/stemmi-squadra/thumbs/NOME.png
