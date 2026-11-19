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
- Press and hold a register to open the matching Garmin glance (heart rate, Body Battery, battery). Connect IQ watch faces receive touch-and-hold only, not plain taps.
- Black ground, so most AMOLED pixels stay off

**Always-on mode:** outlined hands, hour dots, the date and a dim row of heart rate, Body Battery and battery %. No seconds hand. Every minute the whole layout jumps to the next of 25 positions on a 5×5 grid (±10 px), moving at least 10 px on each axis in a changing direction, so wear is spread out and no position repeats within 25 minutes. The face checks the system display mode as well as the sleep callbacks, so it never draws the full face in always-on, and it draws nothing while the display is off.

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
| Heart rate | `Activity.getActivityInfo().currentHeartRate`, falling back to the latest `ActivityMonitor` heart-rate sample (read at most once a minute) |
| Body Battery | Body Battery complication via `Complications.subscribeToUpdates`, falling back to `SensorHistory.getBodyBatteryHistory()` (read at most once a minute) |
| Watch battery | `System.getSystemStats().battery`, rounded once so the number shown and the amber threshold agree |

Permissions: `ComplicationSubscriber` (Body Battery value and press-to-open) and `SensorHistory` (Body Battery fallback).

## Project layout

```
manifest.xml                     app id, Venu 4 41mm/45mm targets, permissions
monkey.jungle
source/
  MeridianApp.mc                 app entry, settings reload
  MeridianView.mc                drawing: dial, registers, hands, always-on
  MeridianDelegate.mc            press and hold a register -> open the Garmin glance
resources/
  settings/                      accent color + seconds hand settings
  strings/strings.xml
  drawables/launcher_icon.png    70×70 base icon
resources-venu441mm/drawables/   54×54 icon for the 41mm
resources-venu445mm/drawables/   65×65 icon for the 45mm
```

All geometry in `MeridianView.mc` is written in a 454 px design space (the 45mm screen) and scaled at draw time, so the 41mm (390 px) gets the same layout. Text sizes are set for the watch's 326 ppi screen (about 13 px per mm), not copied from the design's px: the simulator shows pixels 1:1 on a monitor, so text that looks fine there can be under a millimetre tall on the wrist.

The dial, gauge tracks, labels and date window are drawn once into an offscreen buffer and only redrawn when the accent color or the date changes; each second only the gauge values, numbers and hands are drawn on top.

Weekday names in scripts Roboto doesn't cover (Arabic, Hebrew, Chinese, Japanese, Korean, Thai) are drawn whole in the system font for the watch's language, without letter-spacing.

## Build and run

Requires the Connect IQ SDK and the Venu 4 device files (install both via SDK Manager).

```bash
# one-time: generate a developer key (keep it private, it is git-ignored)
openssl genrsa -out key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out developer_key.der -nocrypt

# the SDK path contains "Application Support", so keep "$SDK/..." quoted
SDK="$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)"
"$SDK/bin/monkeyc" -d venu445mm -f monkey.jungle -o Meridian.prg -y developer_key.der -w -l 3
"$SDK/bin/connectiq"        # start the simulator, wait a few seconds
"$SDK/bin/monkeydo" Meridian.prg venu445mm
```

`-l 3` turns on strict type checking; the project builds clean with it.

Use `-d venu441mm` for the 41mm. In the simulator, set test values under Simulation → Activity Data, and switch to always-on with Settings → Display Mode → Always-On (Off blanks the screen, High Power returns to the full face).

To sideload to a watch, copy the `.prg` to `GARMIN/APPS/` over USB.
