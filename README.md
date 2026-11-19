# Meridian

A three-register analog watch face for the Garmin Venu 4 (41mm / 45mm), written in Monkey C for Connect IQ.

## Face

| Position | Shows | Gauge | Color |
|---|---|---|---|
| 12 o'clock | Date window ("THU 19") | — | Accent |
| 9 o'clock | Heart rate, bpm (`--` with no reading) | 40–200 bpm | Rose |
| 3 o'clock | Body Battery | 0–100 | Sky |
| 6 o'clock | Watch battery % | 0–100% | Sage, amber at 20% or less |

- Faceted ivory hour and minute hands, accent seconds hand with counterweight ring
- Minute track, 5-minute marks, ivory hour indices, double accent bar at 12
- Each register is a 270° gauge opening at the bottom, with icon, value and label
- Tap a register to open the matching Garmin glance (heart rate, Body Battery, battery)
- Black ground, so most AMOLED pixels stay off

**Always-on mode:** outlined hands, hour dots, the date and a dim row of heart rate, Body Battery and battery %. No seconds hand. The whole layout shifts a few pixels every minute so no pixel stays lit long enough to burn in.

## Settings

Edit in Garmin Connect (or in the simulator: File → Edit Persistent Storage → Edit Application.Properties data).

| Setting | Options | Default |
|---|---|---|
| Accent color | Champagne, Ivory, Sky, Rose | Champagne |
| Seconds hand | On / Off | On |

The accent color is used for the 12 o'clock bar, date number, seconds hand and center cap.

## Data sources

| Value | API |
|---|---|
| Heart rate | `Activity.getActivityInfo().currentHeartRate`, falling back to the latest `ActivityMonitor` heart-rate sample |
| Body Battery | Body Battery complication, falling back to `SensorHistory.getBodyBatteryHistory()` |
| Watch battery | `System.getSystemStats().battery` |

Permissions: `ComplicationSubscriber` (Body Battery value and tap-to-open) and `SensorHistory` (Body Battery fallback).

## Project layout

```
manifest.xml                     app id, Venu 4 41mm/45mm targets, permissions
monkey.jungle
source/
  MeridianApp.mc                 app entry, settings reload
  MeridianView.mc                drawing: dial, registers, hands, always-on
  MeridianDelegate.mc            tap a register -> open the Garmin glance
resources/
  settings/                      accent color + seconds hand settings
  strings/strings.xml
  drawables/launcher_icon.png    70×70 base icon
resources-venu441mm/drawables/   54×54 icon for the 41mm
resources-venu445mm/drawables/   65×65 icon for the 45mm
```

All geometry in `MeridianView.mc` is written in a 454 px design space (the 45mm screen) and scaled at draw time, so the 41mm (390 px) gets the same layout.

## Build and run

Requires the Connect IQ SDK and the Venu 4 device files (install both via SDK Manager).

```bash
# one-time: generate a developer key (keep it private, it is git-ignored)
openssl genrsa -out key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out developer_key.der -nocrypt

SDK=$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)
$SDK/bin/monkeyc -d venu445mm -f monkey.jungle -o Meridian.prg -y developer_key.der -w
$SDK/bin/connectiq          # start the simulator, wait a few seconds
$SDK/bin/monkeydo Meridian.prg venu445mm
```

Use `-d venu441mm` for the 41mm. In the simulator, set test values under Simulation → Activity Data, and switch to always-on with Settings → Display Mode → Low Power.

To sideload to a watch, copy the `.prg` to `GARMIN/APPS/` over USB.
