# Read my Script – Plan

Stand 2026-11-17. Privates Werkzeug: Drehbuch-PDF rein, Hörbuch (m4b mit Kapiteln) raus.
Alles lokal auf dem Mac – das Drehbuch verlässt den Rechner nie.

## Entscheidungen (mit Moe abgestimmt)

| Frage | Entscheidung |
|---|---|
| Was liest der Erzähler? | Nur Handlung/Regie. Szenenköpfe, Klammern (fl.), Übergänge werden **nicht** gesprochen. |
| Rollenname vor Dialog? | Nein – Rolle nur an der Stimme erkennbar (Hörspiel). |
| Umfang | ~~Privat, nur Deutsch + Englisch.~~ Seit 2026-11-18: öffentliches GitHub-Repo, Updater (nur GitHub als zweite Gegenstelle), Einstellungsfenster, lokaler Selbsttest ohne Senden, Handbuch, vier Sprachen. |
| Drehbücher | Deutsch und Englisch, beliebige Programme, auch mit Wasserzeichen → Parser muss robust sein. |

## Architektur

```
PDF ──PDFKit──▶ Zeilen mit Position/Farbe/Drehung
     ──Filter──▶ ohne Wasserzeichen, Seitenzahlen, Kopf-/Fußzeilen, Szenennummern
     ──Klassifizierer──▶ Szenenkopf | Handlung | Rolle | Klammer | Dialog | Übergang
     ──Planer──▶ Kapitel (= Szenen) mit Abschnitten (Stimme + Text + Pause)
     ──HTTP 127.0.0.1:3900──▶ VoiceStudio /longform/render (SSE-Fortschritt)
     ──▶ fertige .m4b aus VoiceStudio outputs/ an den gewählten Ort kopieren
```

- **Swift / SwiftUI**, Swift Package wie MarkTheRoughcut: `ScriptCore` (Parser + Planer, ohne UI, voll getestet) + App-Target.
- **PDFKit** liefert Text mit Position pro Zeile – keine Fremd-Bibliothek.
- **Vision** (lokales OCR von Apple) als Rückfall, wenn ein PDF keinen Text hat (Scan).
- **VoiceStudio** macht Sprachsynthese, Kapitel, Zusammenbau, Fortsetzen nach Abbruch. Wir bauen davon nichts nach.

## Parser – robust gegen Formate und Wasserzeichen

1. **Zeilen holen:** pro Seite `selectionsByLine()`, je Zeile: Text, x-Anfang, x-Ende, y, Höhe, Schriftgröße, Farbe.
2. **Störtext entfernen:**
   - gedrehte Zeilen (Wasserzeichen diagonal) → Höhe deutlich über normaler Zeilenhöhe oder Zeichen nicht auf einer Grundlinie
   - helle/transparente Farbe (graue Wasserzeichen)
   - Text, der auf vielen Seiten an gleicher Stelle steht (Kopf-/Fußzeilen, „VERTRAULICH", Name des Empfängers, Seitenzahlen, „(MORE)"/„(WEITER)")
   - stark abweichende Schriftgröße (große Wasserzeichen-Schrift)
   - Szenennummern am Rand links/rechts
3. **Spalten lernen:** Häufigkeit der x-Anfänge über das ganze Buch → Spalte Handlung (links), Dialog (Mitte), Rolle (weiter rechts). Kein fester Abstand – funktioniert für Final Draft, Fade In, WriterDuet, Celtx, Word.
4. **Klassifizieren** (Regeln, deutsch + englisch):
   - Szenenkopf: `INT./EXT./I./A./INNEN/AUSSEN/AUßEN/INNEN/AUSSEN` (+ optionale Nummer), Großbuchstaben
   - Rolle: kurze Zeile in Großbuchstaben in der Rollenspalte, danach Dialog. Zusätze wie `(V.O.)`, `(O.S.)`, `(OFF)`, `(CONT'D)`, `(FORTS.)`, `(WEITER)` werden abgeschnitten → „ANNA (OFF)" = „ANNA".
   - Klammer: beginnt mit `(` unter einer Rolle
   - Dialog: Zeilen in der Dialogspalte nach Rolle/Klammer
   - Übergang: Großbuchstaben mit `:` am Ende oder rechtsbündig (`SCHNITT:`, `CUT TO:`, `ABBLENDE`)
   - Rest: Handlung
   - Rückfall ohne klare Einrückung (Word-Drehbücher): Großbuchstaben-Zeile ≤ 4 Wörter, danach normaler Text = Rolle + Dialog.
5. **Zusammenfügen:** Zeilen eines Absatzes zu einem Text, Silbentrennung am Zeilenende auflösen, Dialog über Seitenwechsel verbinden.
6. Sprache automatisch erkannt (`NLLanguageRecognizer`, lokal), in der App umstellbar.

Testbasis: synthetische Test-PDFs (erzeugt im Test, kein echtes Drehbuch im Repo) in mehreren Layouts, mit diagonalem Wasserzeichen, Kopfzeile, Szenennummern, Scan-Variante.

## Oberfläche (ein Fenster)

1. **Start:** PDF hineinziehen oder öffnen. Status-Punkt „VoiceStudio bereit" (grün) – sonst Hinweis „VoiceStudio starten" mit Knopf.
2. **Besetzung:** Liste Erzähler + alle Rollen (mit Anzahl Zeilen), je Rolle Dropdown mit den VoiceStudio-Stimmen (`GET /profiles`) und „– nicht sprechen –". Vorschlag automatisch (verschiedene Stimmen reihum). Knopf ▶ zum Probehören einer Zeile der Rolle (`/generate`). Zwei Rollen dieselbe Stimme = zusammengelegt (z. B. Fehlerkennung).
3. **Vorschau:** Drehbuch als erkannter Text, Farbe/Markierung pro Element, damit man Fehler sieht. Klick auf eine Zeile → Typ ändern (Handlung/Dialog/ignorieren) für Sonderfälle.
4. **Erstellen:** Ziel wählen, Fortschritt pro Szene, Pause/Abbrechen (VoiceStudio kann abbrechen und fortsetzen). Ergebnis: `<Titel>.m4b`, Kapitel = Szenenköpfe (als Kapitelname, nicht gesprochen).

Einstellungen: Sprache der App (de/en), Hell/Dunkel, Sprache der Sprachausgabe (Auto/Deutsch/Englisch), Pausen (zwischen Szenen, Absätzen, Sprecherwechsel).

## Datenschutz (rechtlicher Grund)

- Die App spricht **nur** mit `127.0.0.1`. Sie hat keinen anderen Netzwerkcode; ein Test prüft, dass im Quelltext keine andere Adresse vorkommt.
- VoiceStudio geprüft (0.5.7): Synthese lokal; Nutzungsstatistik nur nach Opt-in, bei dir aus (`analytics_enabled: false`). Die App prüft beim Start diese Einstellung und warnt deutlich, falls sie an ist.
- VoiceStudio-Funktionen mit Cloud (LLM, Übersetzung, Sync) werden nicht benutzt.
- Log-Datei ohne Drehbuch-Inhalt: nur Dateiname, Anzahl Szenen/Rollen, Fehler.
- Nach dem Erstellen: Zwischendateien in VoiceStudio (`outputs/`, Cache) auf Wunsch löschen.

## Schritte

1. **ScriptCore-Parser** + Test-PDF-Generator + Tests (Layouts, Wasserzeichen, Kopfzeilen, Fortsetzung über Seiten).
2. **Planer** → `/longform/render`-JSON; Test gegen laufendes VoiceStudio mit kurzem Drehbuch.
3. **App-Fenster:** Import, Besetzung, Vorschau, Erstellen mit Fortschritt.
4. **Einstellungen, Log, Datenschutz-Prüfung.**
5. **Test mit deinen echten Drehbüchern** (bleiben außerhalb des Projekts) → Parser nachschärfen.

Offen / später: OCR-Rückfall erst bauen, wenn ein echtes Scan-PDF auftaucht; Aussprache-Lexikon (VoiceStudio kann `lexicon`) für Namen.
