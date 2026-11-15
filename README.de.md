# FnCaps

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Українська](README.uk.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Español](README.es.md) | Deutsch

FnCaps ist eine Menüleisten-App für macOS für alle, die drei oder mehr Eingabequellen verwenden und das Wechseln zwischen ihnen als langsam empfinden.

macOS bietet eine Taste, die alle Eingabequellen nacheinander durchläuft. Bei drei oder mehr drücken Sie so lange, bis die gewünschte Sprache erscheint, prüfen die Menüleiste und drücken erneut.

FnCaps verteilt Ihre Eingabequellen auf zwei Tasten, Caps Lock und fn (🌐).

- Jede Taste hat ihre eigene Liste und wechselt nur innerhalb dieser Liste.
- Sie legen fest, welche Sprache auf welcher Taste liegt. Zum Beispiel Englisch auf Caps Lock und Ihre übrigen Sprachen auf fn.
- Aus einer langen Liste werden zwei kurze. Mit den von FnCaps empfohlenen Belegungen ist die gewünschte Sprache ein oder zwei Tastendrücke entfernt, sodass Ihr Tippen nicht unterbrochen wird.
- Bei mehr Sprachen können Sie einer Eingabequelle einen eigenen Kurzbefehl zuweisen und direkt zu ihr springen.
- Caps Lock wechselt ohne Verzögerung. Halten Sie die Taste, um Caps Lock wie gewohnt ein- oder auszuschalten.

> **Erster Start:** macOS blockiert FnCaps einmal, weil die App nicht von Apple notarisiert ist. Öffnen Sie Systemeinstellungen > Datenschutz & Sicherheit und klicken Sie auf „Trotzdem öffnen“. Die Schritte stehen unter [Trotzdem öffnen](#open-anyway).

> FnCaps befindet sich bis 1.0 in der frühen Entwicklung.

## Voraussetzungen

- macOS 14 Sonoma oder neuer, Apple silicon oder Intel
- Bedienungshilfen-Berechtigung. FnCaps benötigt sie, um fn- und Caps-Lock-Tastendrücke zu erkennen.

## Installation

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

Falls Homebrew Sie zuerst bittet, dem Tap zu vertrauen, führen Sie Folgendes aus und installieren Sie erneut:

```sh
brew trust Seo650/tap
```

### GitHub Releases

1. Laden Sie die neueste `FnCaps-x.y.z.zip` von [Releases](https://github.com/Seo650/FnCaps/releases/latest) herunter.
2. Entpacken Sie sie.
3. Verschieben Sie `FnCaps.app` nach `/Applications`.

## Erster Start

<a id="open-anyway"></a>

### Trotzdem öffnen

FnCaps ist mit einem eigenen Zertifikat signiert und nicht von Apple notarisiert, daher blockiert macOS den ersten Start. Das geschieht einmal.

1. Öffnen Sie FnCaps. macOS meldet, dass die App nicht überprüft werden kann. Klicken Sie auf „Fertig“.
2. Öffnen Sie Systemeinstellungen > Datenschutz & Sicherheit.
3. Klicken Sie unter „Sicherheit“ auf „Trotzdem öffnen“.
4. Geben Sie Ihr Passwort ein oder verwenden Sie Touch ID, und klicken Sie dann auf „Öffnen“.

Die Schaltfläche „Trotzdem öffnen“ erscheint erst nach einem blockierten Start und bleibt etwa eine Stunde lang sichtbar. Wenn sie fehlt, öffnen Sie FnCaps erneut. Wenn Sie die Befehlszeile bevorzugen, hebt Folgendes die Blockierung auf:

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### Einrichtung

Beim Öffnen führt FnCaps Sie durch die Bedienungshilfen-Berechtigung und die Tastenbelegung. FnCaps benötigt die Berechtigung, um fn- und Caps-Lock-Tastendrücke zu erkennen. Alles lässt sich später in den Einstellungen von FnCaps ändern.

## Updates

FnCaps prüft einmal täglich auf eine neue Version. Um sie zu installieren, öffnen Sie die Einstellungen von FnCaps, gehen Sie zu „Über FnCaps“ und klicken Sie auf „Aktualisieren“. Erst mit dem Klick auf „Aktualisieren“ wird etwas installiert. Homebrew-Nutzer aktualisieren auf demselben Weg.

Updates erhalten die Bedienungshilfen-Berechtigung, weil jede Version mit demselben Zertifikat signiert ist.

## Was FnCaps sendet

FnCaps zeichnet nicht auf, was Sie tippen. Es verbindet sich in zwei Fällen mit dem Internet.

- Update-Prüfung: Einmal täglich fragt FnCaps bei der GitHub-API nach der neuesten Version. Die Anfrage enthält die App-Version und nichts weiter über Sie.
- Problem melden: Bis Sie auf „Senden“ klicken, wird nichts gesendet. Eine Meldung enthält Ihre Nachricht, Ihre E-Mail-Adresse, falls Sie eine eingeben, die App- und macOS-Versionen, das Mac-Modell, die Tastaturart, Ihre FnCaps-Einstellungen, Ihre Eingabequellen, das aktuelle Aktivitätsprotokoll und eine zufällige Installationsnummer, die nur für das Tageslimit verwendet wird. Sie enthält nicht, was Sie tippen, keine Seriennummern und keine anderen Gerätekennungen. Sie können alles vor dem Senden lesen. Meldungen werden in einem privaten Repository gespeichert, das nur der Entwickler lesen kann.
- Meldelimits: fünf Meldungen pro Tag je Installation und fünf pro Minute von einer Netzwerkadresse.

## Bekannte Einschränkungen

- Passwortfelder: macOS hält Passwortfelder auf Englisch, daher wechselt FnCaps dort die Sprache nicht, und Halten von Caps Lock schaltet die Feststelltaste nicht ein.
- Control+Space: wechselt die Eingabequelle nicht, solange FnCaps eingeschaltet ist. Es funktioniert wieder, wenn FnCaps ausgeschaltet oder beendet wird.
- Caps-Lock-Leuchte: Wenn Sie Caps Lock durch Halten der Taste einschalten, bleibt die Leuchte auf der Taste aus. Großbuchstaben werden normal eingegeben.
- Sprachindikator: Wenn Sie die Tasten schnell drücken, kann der kleine Indikator, den macOS neben dem Cursor anzeigt, eine andere Sprache zeigen als die verwendete. Die Menüleiste zeigt die richtige.
- Zeichen im Aufbau: Wenn beim Drücken von fn noch ein koreanisches, japanisches oder chinesisches Zeichen zusammengesetzt wird, kann dieses Zeichen verloren gehen.
- Englisches Layout: FnCaps behandelt ABC und U.S. als Englisch. ABC – AZERTY und ABC – QWERTZ zählen als Französisch und Deutsch.
- Karabiner-Elements und gksdud: Diese Apps ändern dieselben Tasten. Eine Karabiner-Regel, die `caps_lock` verwendet, nimmt die Taste an sich, bevor FnCaps sie sieht. FnCaps zeigt eine Warnung, solange eine der beiden läuft.
- Nicht getestet, erwartet funktionsfähig: das Trennen und erneute Anschließen einer externen Tastatur, macOS 14 bis 26 und Macs außer einem MacBook Air mit Apple silicon.

## Wiederherstellung

Wenn Caps Lock nicht mehr funktioniert:

- Wählen Sie in FnCaps „Tasten wiederherstellen“ über das Menüleistensymbol oder klicken Sie in Einstellungen > Allgemein auf „Jetzt wiederherstellen“. Damit werden Caps Lock und der Eingabequellen-Kurzbefehl in den Zustand vor FnCaps zurückversetzt.
- Wenn FnCaps nicht läuft, zum Beispiel nach einem Absturz, kann Caps Lock umbelegt bleiben und nichts tun. Heben Sie die Umbelegung im Terminal auf, und öffnen Sie FnCaps erneut:

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- Wenn Sie dieses Repository geklont haben, hebt das Skript die Umbelegung auf und stellt auch den Eingabequellen-Kurzbefehl wieder her:

  ```sh
  scripts/caps-recover.sh --restore
  ```

Wenn Control+Space nach dem Beenden von FnCaps weiterhin keine Eingabequelle wechselt, prüfen Sie Systemeinstellungen > Tastatur > Tastaturkurzbefehle > Eingabequellen > „Vorherige Eingabequelle auswählen“. „Tasten wiederherstellen“ setzt sie in den Zustand vor FnCaps zurück.

## Deinstallation

Beenden Sie zuerst FnCaps. Das Beenden setzt Caps Lock und den Eingabequellen-Kurzbefehl in den Zustand davor zurück. Führen Sie dann aus:

```sh
brew uninstall --cask fncaps
```

Oder verschieben Sie `FnCaps.app` von `/Applications` in den Papierkorb. Um auch die Einstellungen zu entfernen, verwenden Sie `brew uninstall --zap --cask fncaps`.

## Aus dem Quellcode bauen

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh` erstellt `build/FnCaps.app`. Es signiert mit dem Zertifikat „FnCaps Dev Local“, wenn eines vorhanden ist, andernfalls mit einer Ad-hoc-Signatur. Bei einer Ad-hoc-Signatur fragt macOS nach jedem Build erneut nach der Bedienungshilfen-Berechtigung. `scripts/make-local-identity.sh` erstellt das lokale Zertifikat.

## Mitwirken

Issues und Pull Requests sind willkommen. Die App und diese README sind in zehn Sprachen übersetzt. Die meisten Übersetzungen wurden nicht von Muttersprachlern geprüft, daher sind Korrekturen an Übersetzungen besonders willkommen.

## Lizenz

MIT. Siehe [LICENSE](LICENSE).
