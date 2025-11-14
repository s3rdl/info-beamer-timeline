# info-beamer-timeline

Horizontale Tages-Timeline für info-beamer hosted / pi:

- Zeitfenster 08–23 Uhr
- Events aus `events.json` **oder** inline über Setup-Config (`events_inline`)
- Hintergrund als Bild **oder** Video (MP4/MOV) aus Setup-Config
- Glas-Optik + animierte "Jetzt"-Linie

## Struktur

- `package.json` – Package-Metadaten
- `node.json` – Optionen für das Setup (Hintergrund, Events)
- `node.lua` – Rendering-Logik
- `Roboto-Regular.ttf` – Schriftart (bitte selbst hinzufügen)
- `background.jpg` – Default-Hintergrund (bitte selbst hinzufügen)
- `package.png` – Icon für info-beamer (PNG, <8 kB)

## Events

Du kannst Events entweder in `events.json` (im Package) pflegen:

```json
{
  "events": [
    { "title": "Standup", "start": "09:00", "end": "09:30" },
    { "title": "Workshop", "start": "10:00", "end": "11:30" }
  ]
}