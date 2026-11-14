# CLIferno

Textkürzel für macOS: Kürzel tippen (z. B. `;gitnb`) und CLIferno ersetzt sie systemweit.

## Neueste Version installieren / aktualisieren

Jeder Push auf `main` wird von GitHub Actions getestet, gebaut und als Release
[`latest`](../../releases/tag/latest) veröffentlicht. Installieren oder aktualisieren:

```bash
bash scripts/install.sh
```

Das Skript lädt `CLIferno.zip` aus dem Release `latest`, prüft die SHA-256-Prüfsumme,
signiert die App mit der lokalen Signatur `Atext Local Development` (wird beim ersten Mal
automatisch eingerichtet), beendet ein laufendes CLIferno, installiert nach `/Applications`
(sonst `~/Applications`) und startet die App. Durch die gleichbleibende lokale Signatur
bleiben die Freigaben für Bedienungshilfen und Eingabeüberwachung nach Updates erhalten.

Bei privatem Repository vorher einmal `gh auth login` ausführen. Optionen:
`--tag <tag>` (anderes Release), `--dir <ordner>` (anderer Installationsort).

Die installierte Version steht unten rechts im Fenster „Einträge verwalten“.

## Darstellung (Hell / Dunkel)

Im Fenster oben rechts oder im Menüleisten-Symbol unter **Darstellung**:
*Wie System*, *Hell* oder *Dunkel*. Die Auswahl wird gespeichert.

## Selbst bauen

```bash
bash scripts/setup-signing.sh   # einmalig
bash scripts/build-app.sh       # erzeugt dist/CLIferno.app
swift test
```

## Früherer Name „Atext“

Die App hieß früher Atext. Beim ersten Start zieht CLIferno die gespeicherten Einträge
automatisch von `~/Library/Application Support/Atext` nach `…/CLIferno` um, und der
Installer entfernt eine alte `Atext.app`. Bundle-ID (`dev.local.atext`) und Zertifikatsname
(`Atext Local Development`) bleiben absichtlich gleich, damit macOS die Freigaben für
Bedienungshilfen und Eingabeüberwachung behält.
