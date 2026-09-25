# Demonic Speed Display

iOS-App (SwiftUI + Core Location): zeigt während der Fahrt die aktuelle Geschwindigkeit groß in km/h
und daneben das Tempolimit der befahrenen Straße als Verkehrszeichen. Das Tempolimit kommt aus
OpenStreetMap (`maxspeed`).

> Verkehrszeichen vor Ort sind immer maßgeblich. Die Kartendaten können variable, temporäre oder
> bedingte Limits übersehen.

## Warum OpenStreetMap?

Apple bietet **keine öffentliche API für Tempolimits**. MapKit zeigt Limits zwar in Apple Karten an,
aber weder `MKMapItem`, `MKDirections` noch `MKLocalSearch` stellen sie Apps bereit. Deshalb nutzt die
App die öffentliche [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) und ordnet die
Position selbst einer Straße zu.

## Projekt öffnen und starten

1. `demonicspeeeddisplay.xcodeproj` in **Xcode 16 oder neuer** öffnen (angelegt mit Xcode 26.3).
2. **Simulator:** Schema `demonicspeeeddisplay` wählen, ein iPhone-Simulator, ⌘R.
   Im Simulator startet die App im **Demo-Modus** (violettes „DEMO“-Banner, Testwerte).
   Echte Pipeline im Simulator: Demo-Modus in den Einstellungen ausschalten und in der Simulator-
   Menüleiste *Features → Location → Freeway Drive* wählen. Die Werte sind dann als
   „SIMULIERTE POSITION“ markiert.
3. **iPhone:**
   - iPhone per Kabel verbinden (oder im selben WLAN koppeln) und als Ziel auswählen.
   - *Target → Signing & Capabilities*: dein Team ist eingetragen; bei Bedarf ein anderes Team
     wählen und den Bundle Identifier eindeutig machen.
   - Auf dem iPhone *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* aktivieren (einmalig).
   - ⌘R. Mit einem kostenlosen Apple-Account musst du beim ersten Start unter
     *Einstellungen → Allgemein → VPN & Geräteverwaltung* dem Entwicklerzertifikat vertrauen.
   - Beim ersten Start „Standort freigeben“ → **„Beim Verwenden der App“** und **„Genauer Standort“**.
   - Mindestens iOS 17.
4. Tests: ⌘U (Swift Testing, u. a. `maxspeed`-Auswertung, Straßenzuordnung, Abruf-Drosselung).

## Konfiguration der Tempolimit-Datenquelle

- **Nichts zwingend nötig:** kein API-Schlüssel, kein Konto. Standard ist `https://overpass-api.de/api/interpreter`.
- In der App unter *Einstellungen → Tempolimit-Datenquelle* lässt sich eine andere öffentliche
  Instanz oder ein eigener Overpass-Server (nur `https://`) eintragen.
- Öffentliche Overpass-Server sind kostenlose Gemeinschaftsdienste mit Fair-Use-Grenzen
  (grob 10 000 Abfragen/Tag, begrenzte Parallelität). Für den Eigengebrauch reicht das. Für eine
  Veröffentlichung im App Store sollte ein eigener Server oder ein kommerzieller Anbieter her.
- Lizenz: Daten © OpenStreetMap-Mitwirkende (ODbL). Die Quellenangabe wird in der App angezeigt.

### Anderen Anbieter einbinden

- **Nur Rohdaten austauschen** (eigener OSM-Dienst, Offline-Datei): `RoadGeometrySource`
  implementieren und in `DriveModel.makeProvider` an `OSMSpeedLimitProvider` übergeben. Zuordnung
  und `maxspeed`-Auswertung bleiben erhalten.
- **Anbieter, der Limits selbst liefert** (z. B. HERE, TomTom, Mapbox – jeweils mit eigenem
  API-Schlüssel und Vertrag): `SpeedLimitProvider` implementieren. `resolve(fix:context:)` muss
  schnell sein; Netzwerkabrufe drosselt der Anbieter selbst.

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `App/` | Einstieg, `DriveModel` (verbindet alles), Einstellungen, Netzwerkstatus, Sprachhinweis |
| `Location/` | `LocationService` (CLLocationManager), `LocationFix`, `SpeedValidator` |
| `SpeedLimit/` | Datenquellen-Protokolle, `OverpassClient`, `OSMSpeedLimitProvider` (Cache/Drosselung), `RoadMatcher`, `MaxspeedParser`, Geometrie |
| `Demo/` | Demo-Werte. Diese laufen nie durch die echte Messung oder Datenquelle |
| `UI/` | SwiftUI-Ansichten und Farbschema |

### So arbeitet die Tempolimit-Ermittlung

1. Straßen werden in einem Umkreis von 0,8–2 km geladen, je nach Tempo, und der Mittelpunkt wird
   in Fahrtrichtung vorverlegt. Neu geladen wird erst etwa 12 s vor dem Rand des Bereichs, nach
   15 min oder nach einem Fehler (mit wachsender Wartezeit; bei HTTP 429 so lange, wie der Server vorgibt, sonst 60 s).
   Pro GPS-Wert gibt es **keine** Netzwerkanfrage.
2. Jede GPS-Position wird lokal zugeordnet: Abstand zur Straße (20–45 m, je nach GPS-Genauigkeit),
   Fahrtrichtung gegen Straßenverlauf (≤ 40°), Einbahnstraßen und Kontinuität zur zuletzt
   befahrenen Straße.
3. Liegen mehrere plausible Straßen mit **verschiedenen** Limits dicht beieinander, zeigt die App
   „Tempolimit unbekannt – Straße nicht eindeutig“.
4. „Unbekannt“ erscheint auch, wenn `maxspeed` fehlt, mehrdeutig ist (`50;30`, `walk`) oder
   `maxspeed:conditional`, `maxspeed:variable` bzw. `signals` gesetzt ist, wenn Fahrstreifen
   unterschiedliche Limits haben, wenn ein richtungsabhängiges Limit ohne bekannte Fahrtrichtung
   vorliegt, wenn die geladenen Daten älter als 45 min sind oder wenn Internet bzw. GPS fehlen.
   Aus der Straßenart wird **nie** ein Wert abgeleitet. Nur ausdrückliche gesetzliche Zonenangaben
   im Tag selbst (z. B. `maxspeed=DE:urban` → 50) werden übernommen und als solche gekennzeichnet.

### Wann eine Geschwindigkeit angezeigt wird

Eine Geschwindigkeit erscheint nur, wenn der Messwert höchstens 3 s alt ist, die Position auf 50 m
genau ist, Geschwindigkeit und Geschwindigkeitsgenauigkeit gültig sind (Genauigkeit ≤ 10 km/h) und
der Wert plausibel ist (< 350 km/h). Sonst zeigt die App „– –“ mit Grund. Kommen keine Werte mehr
(z. B. im Tunnel), springt die Anzeige nach 3 s auf „GPS-Signal verloren“.

## Grenzen, die sich technisch nicht zuverlässig lösen lassen

- **Datenqualität von OSM:** Viele Straßen haben kein `maxspeed`. Veraltete oder falsche Einträge
  erkennt die App nicht, denn OSM hat kein verlässliches „geprüft am“ für jedes Limit.
- **Temporäre und variable Limits** (Baustellen, Verkehrsbeeinflussungsanlagen, Schilder nach
  Unfällen) sind in OSM meist gar nicht oder nur als `variable` erfasst.
- **Bedingte Limits** (Uhrzeit, Nässe, Lkw, Schulzeiten) wertet die App nicht aus. Sie zeigt dann
  „unbekannt“, auch wenn die Bedingung gerade nicht gilt.
- **Fahrzeugklassen:** Die Anzeige gilt für Pkw. Anhänger-, Lkw- oder Führerschein-Limits fehlen.
- **Zuordnung:** Bei parallelen Straßen, Brücken/Unterführungen, Parkplätzen neben Straßen,
  engen Kreuzungen und direkt an Limitwechseln kann die App kurz „unbekannt“ zeigen. Bei
  Stillstand hält sie bis zu 60 s die zuletzt sichere Straße. Wer im Stand abbiegt, sieht das
  alte Limit, bis wieder eine Fahrtrichtung messbar ist (ab ca. 10 km/h).
- **GPS:** In Tunneln, Häuserschluchten und Parkhäusern gibt es keine oder ungenaue Werte. Die App
  zeigt dann bewusst nichts an, statt zu schätzen.
- **Nur im Vordergrund:** Ohne Hintergrund-Standort misst die App nur, solange sie geöffnet ist.
  Das ist bewusst so gewählt: Energie, Datenschutz, App-Review.
- **Netz:** Ohne Internet funktioniert nur der schon geladene Umkreis.
- **Datenschutz:** Für die Abfrage wird die Position an den gewählten Overpass-Server gesendet.
- **App-Name:** Der Home-Bildschirm kürzt „Demonic Speed Display“ ggf. ab. Ordner und Target
  heißen weiterhin `demonicspeeeddisplay` (Tippfehler aus der Projektvorlage), damit deine lokale
  Xcode-Konfiguration intakt bleibt.
- Dies ist keine zugelassene Fahrerassistenz. Nicht während der Fahrt bedienen.
