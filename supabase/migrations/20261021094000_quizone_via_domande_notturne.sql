-- QuizOne: tolte le domande della notte del 21/10 (dalle 00:00 alle 07:00), create con la regola precedente.
-- Alla domanda di mezzanotte della Serie F hanno partecipato 2 giocatori gratis (nessuna puntata, nessuna vincita):
-- non c'e' niente da restituire.
delete from public.quizzone_domande
 where extract(hour from ora at time zone 'Europe/Rome') < 8 or extract(hour from ora at time zone 'Europe/Rome') = 23;
