# Meridian

A three-register analog watch face for round-screen Garmin watches, AMOLED and MIP (Venu, vivoactive, Forerunner, fēnix, epix, Enduro, MARQ and more; see [Supported watches](#supported-watches)), written in Monkey C for Connect IQ.

## Face

The date window ("THU 19", accent color) sits at 12. The three registers at 9, 3 and 6 o'clock each show a metric chosen in settings (see [Settings](#settings)); by default heart rate, Body Battery and watch battery. `--` means no reading yet, or a metric the watch doesn't offer.

| Metric | Label | Gauge | Color |
|---|---|---|---|
| Heart rate | BPM | 40–200 bpm | Rose |
| Body Battery | ENERGY | 0–100 | Sky |
| Watch battery | BATTERY | 0–100%; at 20% or less amber, with the label switching to "LOW" | Sage |
| Stress | STRESS | 0–100 | Lavender |
| Steps | STEPS | progress to the step goal | Teal |
| Floors climbed | FLOORS | progress to the floors goal | Khaki |
| Intensity minutes (this week; the setting and help text say so) | INTENSITY | progress to the weekly goal | Gold |
| Calories | KCAL | 0–3,000 kcal (there is no calorie-goal API) | Orange |
| Pulse Ox | SPO2 | 70–100% | Pink |
| Respiration | BRPM | 0–30 breaths per minute | Aqua |
| Sleep score | SLEEP | 0–100 | Indigo |

The colors are for AMOLED; MIP screens get their own from their 64-color palette (see [MIP screens](#mip-screens)).

Values are shown as precisely as fits the register at the current text size: "8432", or "8.4k" at the largest text sizes; 10,000 and up as "12.3k", or "12k" when that doesn't fit. The decimal separator follows the watch language ("12,3k" in German, French, Spanish, Italian, Portuguese and Dutch). A label wider than the register (long translations such as "INTENSIDADE") first loses its letter-spacing, then drops to a smaller font.

- Faceted near-white sword hands (hour 22 px, minute 16 px wide in the 454 px design), 3 px accent seconds hand with counterweight ring
- Minute track with bright 5-minute marks, 7 px ivory hour indices, double accent bar at 12
- Each register is a 270° gauge opening at the bottom, with icon, value and label
- On touchscreen watches, press and hold a register to open the Garmin glance for the metric it shows. Connect IQ watch faces receive touch-and-hold only, not plain taps. The Forerunner 255 family has no touchscreen, so there the registers only display.
- Black ground, so most AMOLED pixels stay off

**Always-on mode:** outlined hands, hour dots, the date and a dim row of the three registers' metrics, in register order (battery and Pulse Ox with %; a battery at 20% or less is drawn in dim amber). No seconds hand. Every minute the whole layout jumps to the next of 25 positions on a 5×5 grid (±10 px), moving at least 10 px on each axis in a changing direction, so wear is spread out and no position repeats within 25 minutes. The face checks the system display mode as well as the sleep callbacks, so it never draws the full face in always-on, and it draws nothing while the display is off.

**Low power on MIP screens:** a MIP screen never turns off and can't burn in, so it keeps the full face in low power instead of the always-on view above. The face is only redrawn once a minute there, so the seconds hand shows only while the watch is awake (a few seconds after you raise your wrist or press a button).

## Supported watches

Every **round color** watch on Connect IQ 5.0 or newer: 69 device profiles in all, 50 AMOLED and 19 MIP, from 218 px (Forerunner 255S) to 466 px (fēnix 9 Pro 51mm). The layout is drawn in a 454 px design space and scaled to the screen, so every size gets the same layout.

### AMOLED

| Family | Models |
|---|---|
| Venu | 2, 2 Plus, 2S, 3, 3S, 4 41mm, 4 45mm / D2 Air X15 |
| vívoactive | 5, 6 |
| Forerunner | 70, 165, 165 Music, 170, 170 Music, 265, 265S, 570 42mm/47mm, 965, 970 |
| fēnix | 8 43mm, 8 47mm/51mm (and tactix 8, quatix 8), 8 Pro, 9 43mm, 9 47mm/51mm, 9 Pro 43mm/47mm/51mm, E |
| epix | Gen 2 (and quatix 7 Sapphire), Pro 42mm, Pro 47mm (and quatix 7 Pro), Pro 51mm (and D2 Mach 1 Pro, tactix 7 AMOLED) |
| MARQ | Gen 2, Gen 2 Aviator, Gen 3 |
| Others | Approach S50, S70 42mm/47mm, S72 43mm/47mm; Descent G2, Mk3 43mm, Mk3i 51mm; D2 Air X10, Mach 1, Mach 2, Mach 2 Pro; Instinct 3 AMOLED 45mm/50mm |

**Fonts differ by watch.** The face asks for Roboto and Roboto Condensed by name. Watches that lack them use their own system fonts instead:
- No Roboto at all (Venu 2/2 Plus/2S, vívoactive 5, D2 Air X10, Descent G2, Approach S50, Instinct 3 AMOLED): labels come out a little larger, and the always-on row may show "8k" where other watches show "8.4k".
- Roboto Condensed only (epix, MARQ Gen 2, Approach S70, Descent Mk3, D2 Mach 1): numbers and the date are in the watch's bold system font.

Everything still fits. Watches without vector fonts have no `Graphics.VectorFont` class at all, so `drawStr` checks that the class exists before testing a font against it. The sleep-score complication is referenced by its number (42) because it was added in API 6.0.2; on older firmware the face builds and shows `--` for it.

### MIP screens

Every round MIP (memory-in-pixel, transflective) watch on Connect IQ 4.2 or newer: 19 device profiles, all with 64-color screens, at 218, 240, 260 and 280 px.

| Family | Models |
|---|---|
| fēnix | 7 (and quatix 7), 7S, 7X (and tactix 7, quatix 7X Solar, Enduro 2), 7 Pro / 7S Pro / 7X Pro (with and without Wi-Fi), 8 Solar 47mm, 8 Solar 51mm (and tactix 8 Solar), 9 Pro Solar 47mm / 51mm |
| Enduro | 3, 4 (Enduro 2 uses the fēnix 7X profile) |
| Forerunner | 255, 255 Music, 255S, 255S Music, 955 / Solar |

The other round MIP watches (fēnix 5/6, Forerunner 245/745/945, vívoactive 3/4, MARQ Gen 1, Descent Mk2, Enduro, Approach S62...) are below Connect IQ 4.2, which the face's complications need.

What changes on MIP (the face checks `DeviceSettings.requiresBurnInProtection`, which is false there):
- **Palette.** These screens show 64 colors, two bits per channel (`00`, `55`, `AA`, `FF`), and round every other color to the nearest one, which would turn the face's warm grays olive or pink and merge several metric colors. So the face uses colors from that palette: white hands, indices and values; `#AAAAAA` labels and minute ticks; `#555555` gauge tracks and date border; accents Champagne `#FFAA55`, Ivory `#FFFFFF`, Sky `#55AAFF`, Rose `#FF5555`; low battery `#FFAA00`. Metric colors: heart rate `#FF5555`, Body Battery `#55AAFF`, battery `#55FF55`, stress `#AAAAFF`, steps `#55AAAA`, floors `#AAAA55`, intensity `#FFFF55`, calories `#FFAA55`, Pulse Ox `#FF55AA`, respiration `#55FFFF`, sleep `#5555FF`.
- **Hands** are flat white: a lighter facet would only dim them on a reflective screen. The near-black register hairline is left out (it would round to black).
- **Low power** keeps the full face without the seconds hand (see above).
- **Fonts.** Most have Roboto Condensed only, like the epix (fēnix 9 Pro Solar 51mm has every face). The Forerunner 255 family has no vector fonts at all, and its smallest system font (bold Roboto) made labels too wide on the 218 px 255S. These watches carry bundled Roboto Condensed bitmap fonts for the labels (`resources-labels-218/260`, 12/9 px and 14/11 px, generated by `tools/bmfont.swift`), selected in `monkey.jungle`; numbers and the date use their system fonts.
- **Touch.** The Forerunner 255 family has no touchscreen, so press-and-hold isn't available there; the settings help says "On touchscreen watches".

**Not supported:** rectangular screens (Venu Sq 2, Venu X1), monochrome screens (Instinct 2/3 Solar, Instinct E, Descent G1), Instinct Crossover AMOLED (its physical hands sit over the screen) and watches below Connect IQ 4.2.

## Settings

Edit in the Connect IQ app or Garmin Connect (or in the simulator: File → Edit Persistent Storage → Edit Application.Properties data). Settings only reach the watch when the face is installed from the Connect IQ Store; a sideloaded copy keeps the defaults. The "Gauges" group's description explains press-and-hold, the short labels and what `--` means, since Garmin Connect has no other place for help text.

| Group | Setting | Options | Default |
|---|---|---|---|
| Gauges | Left gauge (9 o'clock) | Any metric in the table above | Heart rate |
| Gauges | Right gauge (3 o'clock) | Any metric | Body Battery (steps on a watch without it) |
| Gauges | Bottom gauge (6 o'clock) | Any metric | Watch battery |
| Appearance | Accent color | Champagne, Ivory, Sky, Rose | Champagne |
| Appearance | Seconds hand | On / Off | On |

The same metric can sit in more than one register. Which metrics a watch offers depends on its sensors and firmware; one it doesn't offer shows `--`, and press-and-hold does nothing there.

Body Battery is the exception, since it is the right register's default: on a watch that doesn't offer the Body Battery complication, a register set to Body Battery shows steps instead, or, if steps are already on the face, the first of calories, intensity minutes and floors that isn't (`Meridian.slotMetrics`). Press-and-hold then opens that metric's glance. The check runs on the watch, so it needs no device list; none of the watches supported today is known to lack Body Battery. The setting values are the `Meridian.M_*` constants in `MeridianView.mc`, so new metrics must be added at the end of the list.

The accent color is used for the 12 o'clock bar, date number, seconds hand and center cap. With Ivory, the seconds hand and center cap stay champagne so they don't blend into the ivory hour and minute hands.

## Accessibility

Audited against WCAG 2.1 AA, adapted for a watch face.

- **Text size:** all text follows the watch's Font Scale setting (Settings → Display; 0.8–1.4× on Venu 4). Register labels scale up to 1.15× so they still fit between the registers and the hour indices. At the default size, values are about 2 mm tall and labels about 1.3 mm on the 45mm.
- **Contrast:** text is at least 6:1 on black. Graphics needed to read the face are at least 3:1: minute ticks are `#8A8478` (5.7:1; the 3:1 minimum was near-invisible on a real Venu 4), and each gauge's dim track ends in a 7.7:1 tick that marks the top of the scale. The register hairlines and date-window border are decorative. On MIP the metric and accent colors are all at least 4:1 (indigo `#5555FF` is the lowest), labels and ticks `#AAAAAA` 9:1; the `#555555` tracks are decorative, like the AMOLED ones.
- **Not color alone:** at 20% or less the battery label reads "LOW" as well as turning amber. In always-on mode the battery's icon and percentage turn dim amber; the percentage itself is the text cue there.
- **Hands over values:** the hour and minute hands sit on a 2 px black halo, so digits underneath stay distinct from the hand.
- **Language:** labels and settings are translated into German, French, Spanish, Italian, Portuguese, Dutch, Japanese, Korean and Simplified/Traditional Chinese (`resources-<lang>/strings`). The unit labels BPM, KCAL, SPO2 and BRPM stay in English. The Body Battery register is labelled "ENERGY" (Japanese "体力"), which fits under the register and says what the 0–100 score measures; the settings help text ties it to Body Battery. These translations have not been reviewed by native speakers yet. Chinese, Japanese and Korean text uses the watch's own CJK vector fonts at the same size as the Latin labels; Thai, Arabic and Hebrew use the system font for the watch's language, which keeps letter shaping and right-to-left order.
- **Motion:** no flashing; the seconds hand can be turned off.
- **Not possible on the platform:** Connect IQ watch faces have no accessibility tree and Garmin watches have no screen reader, so values can't be announced.

### Store description

Copy for the Connect IQ Store listing, which covers what the face itself can't explain:

> Meridian is a three-register analog face with the date at 12. Choose what each register shows: heart rate, Body Battery, watch battery, stress, steps, floors, intensity minutes, calories, Pulse Ox, respiration or sleep score. By default they show heart rate, Body Battery and watch battery.
>
> On touchscreen watches, press and hold a register to open that metric's Garmin glance. "--" means there's no reading yet, or your watch doesn't offer that metric. "ENERGY" is your Garmin Body Battery, an energy score from 0–100. When the watch battery is at 20% or less, its register turns amber and reads "LOW".
>
> Works on round AMOLED Garmin watches: Venu 2/2 Plus/2S/3/3S/4, vivoactive 5/6, Forerunner 70/165/170/265/570/965/970, fēnix 8/9/E, epix (Gen 2)/Pro, MARQ (Gen 2/3), Descent G2/Mk3, Approach S50/S70/S72, D2 Air X10/X15/Mach, Instinct 3 AMOLED.
>
> And on round MIP watches: fēnix 7/7S/7X and 7 Pro, fēnix 8 Solar, fēnix 9 Pro Solar, Enduro 2/3/4, Forerunner 255/255S/955, with colors tuned for their 64-color screens.
>
> Text follows your watch's Font Scale setting. On AMOLED watches, always-on mode shows outlined hands, the date and a dim row of your three metrics, and shifts slightly each minute to protect the display. MIP watches keep the full face in low power, without the seconds hand.

## Data sources

Only the metrics on the face are read or subscribed to. Complication and history values outside a metric's range (0–100; Pulse Ox 50–100; respiration up to 60) count as no reading, so a "couldn't measure" code never shows as a number.

| Value | API |
|---|---|
| Heart rate | `Activity.getActivityInfo().currentHeartRate`, falling back to the latest `ActivityMonitor` heart-rate sample (read at most once a minute) |
| Body Battery, stress, Pulse Ox | Their complications via `Complications.subscribeToUpdates`, falling back to `SensorHistory` (Body Battery, stress, oxygen saturation history; read at most once a minute). A history sample older than 2 hours (Pulse Ox: 24 hours, as it is mostly measured overnight) shows `--` instead |
| Respiration | `ActivityMonitor.getInfo().respirationRate`, falling back to the respiration complication |
| Sleep score | Sleep score complication only |
| Steps, floors, intensity minutes, calories | `ActivityMonitor.getInfo()` (with `stepGoal`, `floorsClimbedGoal`, `activeMinutesWeekGoal` for the gauges) |
| Watch battery | `System.getSystemStats().battery`, rounded once so the number shown and the amber threshold agree |

Press-and-hold opens each metric's complication with `Complications.exitTo`.

Permissions: `ComplicationSubscriber` (complication values and press-to-open) and `SensorHistory` (history fallbacks).

## Project layout

```
manifest.xml                     app id, the 69 round AMOLED and MIP targets, permissions
monkey.jungle                    bundled label fonts for the Forerunner 255 family
source/
  MeridianApp.mc                 app entry, settings reload
  MeridianView.mc                drawing: dial, registers, hands, always-on
  MeridianDelegate.mc            press and hold a register -> open the Garmin glance
resources/
  settings/                      register metrics, accent color, seconds hand; help text
  strings/strings.xml            English strings (labels, settings)
  drawables/launcher_icon.png    70×70 base icon
resources-<lang>/strings/        translations (deu fre spa ita por dut jpn kor zhs zht)
resources-venu441mm/drawables/   54×54 icon for the 41mm
resources-venu445mm/drawables/   65×65 icon for the 45mm
resources-labels-218/fonts/      Roboto Condensed label fonts, Forerunner 255S/255S Music
resources-labels-260/fonts/      the same for the Forerunner 255/255 Music
tools/bmfont.swift               renders a TTF to a BMFont (.fnt + .png) for those
```

To regenerate the label fonts (Roboto Condensed comes with the SDK Manager's device fonts):

```bash
TTF="$HOME/Library/Application Support/Garmin/ConnectIQ/Fonts/RobotoCondensed-Regular.ttf"
CH=" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝ"
swift tools/bmfont.swift "$TTF" 12 "$CH" resources-labels-218/fonts label
swift tools/bmfont.swift "$TTF" 9 "$CH" resources-labels-218/fonts label_small
swift tools/bmfont.swift "$TTF" 14 "$CH" resources-labels-260/fonts label
swift tools/bmfont.swift "$TTF" 11 "$CH" resources-labels-260/fonts label_small
```

The sizes match what `Graphics.getVectorFont` gets on other watches: `LABEL_PX` (24) times the screen scale, and 0.82× that.

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

Use `-d venu441mm` for the 41mm, or any id from `manifest.xml` (for example `fenix7`, `fr255s`) for other watches; each needs its device files from SDK Manager. In the simulator, set test values under Simulation → Activity Data, and switch to always-on with Settings → Display Mode → Always-On (Off blanks the screen, High Power returns to the full face).

To sideload to a watch, copy the `.prg` to `GARMIN/APPS/` over USB.

### CI

`.github/workflows/build.yml` builds with `-l 3` on every push to `main`, every pull request and on demand, for four profiles that cover the screen and font paths: `venu445mm` (AMOLED), `venu2` (AMOLED without Roboto), `fenix7` (MIP) and `fr255s` (MIP with the bundled bitmap label fonts). It downloads the SDK and device files with [connect-iq-sdk-manager](https://github.com/lindell/connect-iq-sdk-manager-cli), and signs with a throwaway key. The download needs a Garmin login token in the `GARMIN_TOKEN` repository secret:

```bash
brew install lindell/connect-iq-sdk-manager-cli/connect-iq-sdk-manager
connect-iq-sdk-manager login      # opens Garmin sign-in in the browser; two-step verification works
gh secret set GARMIN_TOKEN < ~/.Garmin/ConnectIQ/token.json
```

The token expires; the build warns two weeks before, and then the same steps renew it.
