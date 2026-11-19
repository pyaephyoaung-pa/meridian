# Meridian

A three-register analog watch face for the Garmin Venu 4 (41mm / 45mm), written in Monkey C for Connect IQ.

## Face

| Position | Shows | Gauge | Color |
|---|---|---|---|
| 12 o'clock | Date window ("THU 19") | — | Accent |
| 9 o'clock | Heart rate, bpm (`--` with no reading) | 40–200 bpm | Rose |
| 3 o'clock | Body Battery, labelled "ENERGY" | 0–100 | Sky |
| 6 o'clock | Watch battery % | 0–100% | Sage; at 20% or less amber, with the label switching to "LOW" |

- Faceted ivory hour and minute hands, accent seconds hand with counterweight ring
- Minute track, 5-minute marks, ivory hour indices, double accent bar at 12
- Each register is a 270° gauge opening at the bottom, with icon, value and label
- Press and hold a register to open the matching Garmin glance (heart rate, Body Battery, battery). Connect IQ watch faces receive touch-and-hold only, not plain taps.
- Black ground, so most AMOLED pixels stay off

**Always-on mode:** outlined hands, hour dots, the date and a dim row of heart rate, Body Battery and battery %. No seconds hand. Every minute the whole layout jumps to the next of 25 positions on a 5×5 grid (±10 px), moving at least 10 px on each axis in a changing direction, so wear is spread out and no position repeats within 25 minutes. The face checks the system display mode as well as the sleep callbacks, so it never draws the full face in always-on, and it draws nothing while the display is off.

## Settings

Edit in Garmin Connect (or in the simulator: File → Edit Persistent Storage → Edit Application.Properties data). Both settings sit in an "Appearance" group whose description explains press-and-hold and what `--` means, since Garmin Connect has no other place for help text.

| Setting | Options | Default |
|---|---|---|
| Accent color | Champagne, Ivory, Sky, Rose | Champagne |
| Seconds hand | On / Off | On |

The accent color is used for the 12 o'clock bar, date number, seconds hand and center cap. With Ivory, the seconds hand and center cap stay champagne so they don't blend into the ivory hour and minute hands.

## Accessibility

Audited against WCAG 2.1 AA, adapted for a watch face.

- **Text size:** all text follows the watch's Font Scale setting (Settings → Display; 0.8–1.4× on Venu 4). Register labels scale up to 1.15× so they still fit between the registers and the hour indices. At the default size, values are about 2 mm tall and labels about 1.3 mm on the 45mm.
- **Contrast:** text is at least 6:1 on black. Graphics needed to read the face are at least 3:1: minute ticks are `#5D5950`, and each gauge's dim track ends in a 7.7:1 tick that marks the top of the scale. The register hairlines and date-window border are decorative.
- **Not color alone:** at 20% or less the battery label reads "LOW" as well as turning amber.
- **Hands over values:** the hour and minute hands sit on a 2 px black halo, so digits underneath stay distinct from the hand.
- **Language:** labels and settings are translated into German, French, Spanish, Italian, Portuguese, Dutch, Japanese, Korean and Simplified/Traditional Chinese (`resources-<lang>/strings`). "BPM" stays in English. The Body Battery register is labelled "ENERGY" (Japanese "体力"), which fits under the register and says what the 0–100 score measures; the settings help text ties it to Body Battery. These translations have not been reviewed by native speakers yet. Chinese, Japanese and Korean text uses the watch's own CJK vector fonts at the same size as the Latin labels; Thai, Arabic and Hebrew use the system font for the watch's language, which keeps letter shaping and right-to-left order.
- **Motion:** no flashing; the seconds hand can be turned off.
- **Not possible on the platform:** Connect IQ watch faces have no accessibility tree and Garmin watches have no screen reader, so values can't be announced.

### Store description

Copy for the Connect IQ Store listing, which covers what the face itself can't explain:

> Meridian is a three-register analog face: heart rate at 9, Body Battery at 3, watch battery at 6 and the date at 12.
>
> Press and hold a register to open its glance (heart rate, Body Battery or battery). "--" means there's no reading yet, for example right after you put the watch on. "ENERGY" is your Garmin Body Battery, an energy score from 0–100. When the watch battery is at 20% or less, its register turns amber and reads "LOW".
>
> Text follows your watch's Font Scale setting. In always-on mode the face shows outlined hands, the date and a dim row of heart rate, Body Battery and battery, and shifts slightly each minute to protect the display.

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
  settings/                      accent color + seconds hand settings, help text
  strings/strings.xml            English strings (labels, settings)
  drawables/launcher_icon.png    70×70 base icon
resources-<lang>/strings/        translations (deu fre spa ita por dut jpn kor zhs zht)
resources-venu441mm/drawables/   54×54 icon for the 41mm
resources-venu445mm/drawables/   65×65 icon for the 45mm
```

All geometry in `MeridianView.mc` is written in a 454 px design space (the 45mm screen) and scaled at draw time, so the 41mm (390 px) gets the same layout. Text sizes are set for the watch's 326 ppi screen (about 13 px per mm), not copied from the design's px: the simulator shows pixels 1:1 on a monitor, so text that looks fine there can be under a millimetre tall on the wrist.

The dial, gauge tracks, labels and date window are drawn once into an offscreen buffer and only redrawn when the accent color, the date, the Font Scale setting or the low-battery state changes; each second only the gauge values, numbers and hands are drawn on top.

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
