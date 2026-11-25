# DimMA Preheater 🔥💡

grandMA3-Plugin, das per Knopfdruck einen eigenen **Dimmer-Fixture-Type** (8 bit oder 16 bit) mit einstellbarem **Preheat** und **Limit** erstellt – ohne Vorlage, ohne manuelles Importieren.

- **Preheat** = DMX-Ausgabe bei 0 % (Lampe bleibt vorgeglüht)
- **Limit** = DMX-Ausgabe bei 100 %

Der Fixture-Type wird automatisch nach den Werten benannt, z. B. `Dimmer 16bit PH5 L90`.

## Installation

1. `DimMA_Preheater.xml` und `DimMA_Preheater.lua` kopieren nach
   - USB-Stick: `grandMA3/gma3_library/datapools/plugins/`
   - onPC: `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\`
2. In grandMA3 im Plugin-Pool einen leeren Platz wählen → **Import** → **DimMA Preheater**.

## Benutzung

Plugin antippen → Dialog:

| Feld      | Bedeutung                     |
|-----------|-------------------------------|
| Auflösung | 8 bit oder 16 bit             |
| Preheat % | Ausgabe bei Dimmer 0 %        |
| Limit %   | Ausgabe bei Dimmer 100 %      |

Oder ohne Dialog über die Command Line (Bit, Preheat %, Limit %):

```
Plugin "DimMA Preheater" "16,5,90"
```

## Was das Plugin macht

1. Schreibt eine grandMA3-Fixture-Type-Datei (`DimMA@Dimmer …@v1.xml`) in die User-Fixture-Library.
2. Importiert sie in `ShowData.Patch.FixtureTypes` auf die nächste freie Nummer
   (`Import <Nr> /File "…" /Path "…"`, Fallback: Lua `Acquire():Import()`).

Aufbau des DMX-Kanals:

```
DMX-Kanal (Coarse, bei 16 bit + Fine)
└─ LogicalChannel Dimmer
     ├─ "Dimmer"      Preheat … Limit   → Dimmer 0 … 100 %
     └─ "Over Limit"  Limit+1 … Max     (NoFeature, nur wenn Limit < 100 %)
```

## Hinweise

- Gibt es schon einen Fixture-Type mit gleichem Namen, wird kein neuer angelegt – alten vorher löschen.
- Klappt der automatische Import nicht, meldet das Plugin den Dateipfad; dann über
  **Patch → Fixture Types → Import** von Hand auswählen.
- Entwickelt für grandMA3 2.x (Fixture-XML DataVersion 2.3.2.0).
