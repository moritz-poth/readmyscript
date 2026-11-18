# Read my Script

Read my Script macht aus einem Drehbuch-PDF ein Hörbuch. Ein Erzähler liest die Handlung, und jede Rolle spricht mit eigener Stimme. Die Stimmen kommen aus **VoiceStudio**, das auf demselben Mac läuft.

## Dein Drehbuch bleibt auf diesem Mac

- Das Drehbuch geht nur an VoiceStudio auf diesem Computer (Adresse 127.0.0.1) – nie ins Internet.
- Die einzige Verbindung ins Internet ist die Frage an GitHub, ob es eine neue Version von Read my Script gibt. Sie enthält nichts aus deinen Drehbüchern.
- Die Log-Datei listet, was die App getan hat – ohne Text aus deinen Drehbüchern.
- Read my Script warnt, wenn in VoiceStudio die Nutzungsstatistik oder die Cloud-Synchronisierung an ist. Schalte beides in VoiceStudio aus, bevor du ein Drehbuch vorlesen lässt.

## Bevor es losgeht

- Installiere und öffne **VoiceStudio**. Der Punkt oben rechts wird grün, sobald es bereit ist; sonst klicke **VoiceStudio starten**.
- Lege in VoiceStudio ein paar Stimmen an – oder baue neue direkt in Read my Script (siehe „Eine neue Stimme“).

## Drehbuch öffnen

Zieh ein Drehbuch-PDF auf das Fenster oder nutze **Ablage → PDF öffnen…** (⌘O). Read my Script erkennt Szenenköpfe, Handlung, Rollennamen, Regieanweisungen in Klammern, Dialoge und Übergänge – in Drehbüchern aus Final Draft, Fade In, Word und anderen Programmen, auf Deutsch und Englisch. Seitenzahlen, Szenennummern, Kopfzeilen und Wasserzeichen bleiben weg.

- Alles vor dem ersten Szenenkopf (Titelseite, Notizen) wird nicht gelesen. Die Besetzungsliste sagt, wie viele Absätze das sind.
- PDFs aus eingescannten Seiten enthalten keinen Text und können noch nicht gelesen werden.

## Besetzung

Die linke Spalte zeigt den **Erzähler** und alle Rollen, die mit den meisten Repliken zuerst. Wähle für jede eine Stimme aus ihrem Menü; ▶ spielt eine Replik der Rolle in dieser Stimme vor.

- **Eine Stimme pro Rolle:** Read my Script vergibt eine Stimme nie von sich aus an zwei Rollen. Gibt es mehr Rollen als Stimmen, steht bei den übrigen **Stimme wählen**. Wählst du eine Stimme, die schon jemand spricht, fragt die App nach – Zuhörer unterscheiden die Rollen nur an der Stimme.
- **Nicht lesen** lässt eine Rolle bewusst weg.
- Solange eine Rolle keine Stimme hat, lässt sich das Hörbuch nicht erstellen – so fehlen keine Repliken unbemerkt.

## Eine neue Stimme

**Neue Stimme…** unten in jedem Stimmen-Menü baut in VoiceStudio eine Stimme aus wenigen Merkmalen: Geschlecht, Alter, Tonhöhe und Flüstern. **Anhören** spielt die erste Replik der Rolle, **Andere Variante** liefert eine andere Stimme mit denselben Merkmalen. **Stimme speichern** legt sie in VoiceStudio ab und gibt sie der Rolle.

## Text prüfen

Die rechte Spalte zeigt das Drehbuch so, wie es gelesen wird. Mit einem Rechtsklick auf einen Absatz lässt du ihn **vom Erzähler lesen**, **nicht lesen** oder wieder **wie erkannt** behandeln.

## Hörbuch erstellen

Wähle unten die **Sprache der Stimmen** (Automatisch, Deutsch oder Englisch), klicke **Hörbuch erstellen…** und wähle den Speicherort. Heraus kommt ein `.m4b`-Hörbuch mit einem Kapitel pro Szene.

- Das dauert lange: auf einem Mac mit Apple Silicon etwa siebenmal so lange wie die Spielzeit – ein 90-Minuten-Drehbuch braucht rund zehn Stunden. Lass es über Nacht laufen.
- **Pause** hält VoiceStudio an; fertige Szenen bleiben erhalten, **Fortsetzen** macht dort weiter. **Abbrechen** verwirft das halbfertige Hörbuch.

## Einstellungen

**Read my Script → Einstellungen…** (⌘,):

- **Allgemein:** helle oder dunkle Darstellung, Sprache (die App startet neu).
- **Updates:** Version, nach Updates suchen, Testversionen. Ein Hinweis oben im Fenster bietet neue Versionen an; die Installation startet die App neu.
- **Support:** ein Selbsttest mit erfundenen Testdrehbüchern (es wird nichts gesendet), die Log-Datei und ein Kaffee, wenn dir die App gefällt.
- **Über:** Version, Lizenz und Quellcode.
