import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Meridian — three-register analog face for Venu 4, date at 12.
// Each register (9, 3 and 6 o'clock) shows a metric chosen in settings;
// by default heart rate, Body Battery and watch battery.
//
// All geometry is written in the design's 454 px space (Venu 4 45mm) and
// scaled by w/454 at draw time, so every round screen from 218 px
// (Forerunner 255S) to 466 px gets the same layout.
// Shared with MeridianDelegate for press hit-testing.
module Meridian {
    const SIZE   = 454.0;
    const C      = 227.0;    // center
    const SUB_R  = 58.0;     // subdial gauge radius

    // Register slots: left (9 o'clock), right (3), bottom (6)
    const SLOT_X = [119.0, 335.0, 227.0];
    const SLOT_Y = [227.0, 227.0, 335.0];
    const SLOT_KEYS = ["GaugeLeft", "GaugeRight", "GaugeBottom"];
    const SLOT_DEFAULTS = [0, 1, 2];

    // Metrics a register can show. The values are the settings' list values,
    // so never renumber them; add new metrics at the end.
    const M_HEART_RATE   = 0;
    const M_BODY_BATTERY = 1;
    const M_BATTERY      = 2;
    const M_STRESS       = 3;
    const M_STEPS        = 4;
    const M_FLOORS       = 5;
    const M_INTENSITY    = 6;
    const M_CALORIES     = 7;
    const M_PULSE_OX     = 8;
    const M_RESPIRATION  = 9;
    const M_SLEEP        = 10;
    const METRIC_COUNT   = 11;

    // Garmin complication per metric: press-and-hold opens its glance, and
    // for some metrics it also pushes the live value
    const COMPLICATIONS = [
        Complications.COMPLICATION_TYPE_HEART_RATE,
        Complications.COMPLICATION_TYPE_BODY_BATTERY,
        Complications.COMPLICATION_TYPE_BATTERY,
        Complications.COMPLICATION_TYPE_STRESS,
        Complications.COMPLICATION_TYPE_STEPS,
        Complications.COMPLICATION_TYPE_FLOORS_CLIMBED,
        Complications.COMPLICATION_TYPE_INTENSITY_MINUTES,
        Complications.COMPLICATION_TYPE_CALORIES,
        Complications.COMPLICATION_TYPE_PULSE_OX,
        Complications.COMPLICATION_TYPE_RESPIRATION_RATE,
        // COMPLICATION_TYPE_SLEEP_SCORE (API 6.0.2) by value, so watches on
        // older firmware still build; there it isn't offered and shows "--"
        42 as Complications.Type
    ];

    // Shown instead of Body Battery on a watch that doesn't have it (the
    // right register's default): the first of these no other register shows
    const BODY_BATTERY_STAND_INS = [M_STEPS, M_CALORIES, M_INTENSITY, M_FLOORS];

    var _bbChecked as Boolean = false;
    var _bbOffered as Boolean = true;

    // Metric shown in a slot, from settings
    function slotMetric(slot as Number) as Number {
        return slotMetrics()[slot] as Number;
    }

    // Metrics of all three slots: an unknown value falls back to that slot's
    // default, and Body Battery gets a stand-in where the watch lacks it
    function slotMetrics() as Array<Number> {
        var ms = [settingMetric(0), settingMetric(1), settingMetric(2)] as Array<Number>;
        if (!bodyBatteryOffered()) {
            for (var i = 0; i < 3; i++) {
                if (ms[i] == M_BODY_BATTERY) {
                    for (var j = 0; j < BODY_BATTERY_STAND_INS.size(); j++) {
                        var c = BODY_BATTERY_STAND_INS[j] as Number;
                        if (ms.indexOf(c) < 0) {
                            ms[i] = c;
                            break;
                        }
                    }
                }
            }
        }
        return ms;
    }

    function settingMetric(slot as Number) as Number {
        var v = Application.Properties.getValue(SLOT_KEYS[slot] as String);
        if (v instanceof Number && v >= 0 && v < METRIC_COUNT) {
            return v;
        }
        return SLOT_DEFAULTS[slot] as Number;
    }

    // Every watch with Body Battery offers it as a complication. Checked once.
    function bodyBatteryOffered() as Boolean {
        if (!_bbChecked) {
            _bbChecked = true;
            try {
                _bbOffered = Complications.getComplication(
                    new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY)) != null;
            } catch (e) {
                _bbOffered = false;
            }
        }
        return _bbOffered;
    }

    typedef Font as Graphics.VectorFont or Graphics.FontType;
}

class MeridianView extends WatchUi.WatchFace {

    // ---- Palette (see design "States & tokens") ----
    // Contrast on black: text >= 6:1; graphics needed to read the face >= 3:1.
    // These are the AMOLED colors; on MIP screens loadPalette() swaps the main
    // face's colors for ones from the 64-color palette.
    private const C_BLACK     = 0x000000;  // ground, pixels off
    private const C_IVORY     = 0xEDE6D6;  // indices, values
    private const C_HAND      = 0xFFF8EC;  // hour + minute hands, brighter than the indices
    private const C_FACET     = 0xD9CFBC;  // hand facets, light so the whole hand reads bright
    private const C_GRAPHITE  = 0x2B2925;  // gauge tracks (decorative; the scale ends are marked)
    private const C_ASH       = 0x8F897D;  // labels
    private const C_AMBER     = 0xF29A45;  // battery at 20% or less
    private const C_TICK_MIN  = 0x8A8478;  // minute ticks (5.7:1; 3:1 was near-invisible on device)
    private const C_TICK_5    = 0xA39C8E;  // gauge end-of-scale tick
    private const C_TICK_HOUR = 0xD6CEBD;  // 5-minute marks on the minute track
    private const C_SUB_RING  = 0x1C1B18;  // subdial inner hairline (decorative)
    private const C_DATE_EDGE = 0x3A3731;  // date window border (decorative)
    private const C_CHAMPAGNE = 0xD4B37A;
    // Always-on
    private const C_AOD_DOT   = 0x6B665C;
    private const C_AOD_AMBER = 0xC27E3D;  // low battery in the metrics row, dimmed like the rest
    private const C_AOD_MARK  = 0x9C8559;
    private const C_AOD_LINE  = 0xA39C8E;

    // Accent (setting AccentColor): Champagne, Ivory, Sky, Rose
    private const ACCENTS = [0xD4B37A, 0xEDE6D6, 0x6DB5E3, 0xE8735E];
    private const ACCENT_IVORY = 1;

    // Gauge and icon color per metric (Meridian.M_*), all >= 3:1 on black
    private const METRIC_COLORS = [
        0xE8735E,  // heart rate: rose
        0x6DB5E3,  // Body Battery: sky
        0xA8CF96,  // watch battery: sage (amber when low)
        0xB79CE6,  // stress: lavender
        0x6CC4B0,  // steps: teal
        0xC9B48A,  // floors: khaki
        0xE6C35C,  // intensity minutes: gold
        0xF0885A,  // calories: orange
        0xE87A9A,  // Pulse Ox: pink
        0x7DD3E8,  // respiration: aqua
        0x8E9CF0   // sleep score: indigo
    ];

    // MIP screens (fēnix 7, fēnix 8 Solar, Enduro, Forerunner 255/955) show
    // 64 colors, two bits per channel (00, 55, AA, FF). Any other color is
    // rounded to the nearest one, which turns the warm grays above olive or
    // pink and merges several metric colors, so there the face uses these,
    // picked from that palette (see loadPalette).
    private const MIP_ACCENTS = [0xFFAA55, 0xFFFFFF, 0x55AAFF, 0xFF5555];
    private const MIP_METRIC_COLORS = [
        0xFF5555,  // heart rate: rose
        0x55AAFF,  // Body Battery: sky
        0x55FF55,  // watch battery: green
        0xAAAAFF,  // stress: lavender
        0x55AAAA,  // steps: teal
        0xAAAA55,  // floors: khaki
        0xFFFF55,  // intensity minutes: yellow
        0xFFAA55,  // calories: orange
        0xFF55AA,  // Pulse Ox: pink
        0x55FFFF,  // respiration: aqua
        0x5555FF   // sleep score: indigo
    ];

    // Icons per metric in a 24-unit viewBox, as drawing ops:
    // [0, x0, y0, ...] polygon (filled on the main face, outlined in always-on),
    // [1, x0, y0, ...] polyline, [2, cx, cy, r] circle. The battery icon is
    // drawn separately (it shows the charge level). Heart sampled from the
    // design's SVG path.
    private const ICONS = [
        [[0.0, 12.0, 20.5, 10.8, 19.7, 8.0, 17.6, 4.9, 14.7, 2.7, 11.3, 2.3, 8.8,
          3.0, 6.6, 4.7, 5.1, 7.0, 4.5, 8.4, 4.7, 9.7, 5.3, 10.9, 6.2,
          12.0, 7.4, 13.1, 6.2, 14.3, 5.3, 15.6, 4.7, 17.0, 4.5, 19.3, 5.1,
          21.0, 6.6, 21.7, 8.8, 21.3, 11.3, 19.1, 14.7, 16.0, 17.6, 13.2, 19.7]],
        [[0.0, 13.5, 2.0, 5.0, 13.5, 11.2, 13.5, 10.0, 22.0, 18.5, 10.5, 12.3, 10.5]],
        [],
        // stress: jagged line
        [[1.0, 2.0, 12.0, 6.0, 5.0, 10.0, 19.0, 14.0, 5.0, 18.0, 19.0, 22.0, 12.0]],
        // steps: two footprints (sole + heel each)
        [[0.0, 11.0, 6.4, 11.1, 9.2, 10.2, 11.4, 8.5, 12.5, 6.6, 12.2, 4.8, 10.5, 3.8, 8.0, 3.7, 5.2, 4.6, 3.0, 6.3, 1.9, 8.2, 2.2, 10.0, 3.9],
         [0.0, 9.2, 15.8, 9.0, 17.3, 7.8, 18.5, 6.1, 18.8, 4.6, 18.3, 3.8, 17.0, 4.0, 15.5, 5.2, 14.3, 6.9, 14.0, 8.4, 14.5],
         [0.0, 20.2, 11.4, 19.2, 13.9, 17.4, 15.6, 15.5, 15.9, 13.8, 14.8, 12.9, 12.6, 13.0, 9.8, 14.0, 7.3, 15.8, 5.6, 17.7, 5.3, 19.4, 6.4, 20.3, 8.6],
         [0.0, 20.2, 20.4, 19.4, 21.7, 17.9, 22.2, 16.2, 21.9, 15.0, 20.7, 14.8, 19.2, 15.6, 17.9, 17.1, 17.4, 18.8, 17.7, 20.0, 18.9]],
        // floors: stairs
        [[0.0, 3.0, 21.0, 3.0, 16.5, 8.0, 16.5, 8.0, 12.0, 13.0, 12.0, 13.0, 7.5, 18.0, 7.5, 18.0, 3.0, 21.0, 3.0, 21.0, 21.0]],
        // intensity minutes: stopwatch
        [[2.0, 12.0, 13.5, 7.5], [1.0, 12.0, 13.5, 12.0, 9.0], [1.0, 12.0, 13.5, 15.0, 15.5],
         [1.0, 9.5, 3.0, 14.5, 3.0], [1.0, 12.0, 3.0, 12.0, 6.0]],
        // calories: flame, with a side tongue so it doesn't read as the Pulse Ox drop
        [[0.0, 13.0, 1.5, 16.5, 6.5, 19.0, 11.0, 19.5, 15.0, 17.5, 19.5, 13.5, 22.0, 10.5, 22.0,
          6.5, 19.5, 4.5, 15.5, 5.0, 11.5, 7.0, 7.5, 9.0, 12.5, 10.5, 7.5, 12.0, 4.5]],
        // Pulse Ox: drop
        [[0.0, 12.0, 2.5, 15.5, 8.0, 18.5, 12.5, 19.0, 16.0, 17.0, 19.8, 12.0, 21.8,
          7.0, 19.8, 5.0, 16.0, 5.5, 12.5, 8.5, 8.0]],
        // respiration: air waves
        [[1.0, 3.0, 8.0, 6.0, 6.5, 9.0, 8.0, 12.0, 9.5, 15.0, 8.0],
         [1.0, 3.0, 13.0, 7.0, 11.0, 11.0, 13.0, 15.0, 15.0, 19.0, 13.0, 21.0, 12.0],
         [1.0, 3.0, 18.0, 6.0, 16.5, 9.0, 18.0, 12.0, 19.5, 15.0, 18.0]],
        // sleep score: crescent moon
        [[0.0, 20.7, 14.3, 19.8, 16.5, 18.4, 18.4, 16.5, 19.8, 14.3, 20.7, 12.0, 21.0, 9.7, 20.7,
          7.5, 19.8, 5.6, 18.4, 4.2, 16.5, 3.3, 14.3, 3.0, 12.0, 3.3, 9.7, 4.2, 7.5, 5.6, 5.6,
          7.5, 4.2, 9.7, 3.3, 9.8, 4.4, 9.0, 6.1, 8.8, 8.0, 9.0, 9.9, 9.8, 11.6, 10.9, 13.1,
          12.4, 14.2, 14.1, 15.0, 16.0, 15.2, 17.9, 15.0, 19.6, 14.2]]
    ];

    // Sword hands, design space, clockwise from the tip:
    // [tip, right shoulder, right base, tail, left base, left shoulder].
    // Hour 22 px wide reaching r130; minute 16 px wide reaching the minute track.
    private const HOUR_HAND   = [227.0,  97.0, 238.0, 134.0, 234.5, 212.0, 227.0, 249.0, 219.5, 212.0, 216.0, 134.0];
    private const MINUTE_HAND = [227.0,  23.0, 235.0,  66.0, 233.0, 212.0, 227.0, 251.0, 221.0, 212.0, 219.0,  66.0];

    // ---- Layout, design px ----
    // Gauge: 270° opening at the bottom. Dc.drawArc degrees (0 = 3 o'clock,
    // counter-clockwise), so it starts at 7:30 and runs clockwise to 4:30.
    private const GAUGE_START = 225;
    private const GAUGE_END   = 315;
    private const GAUGE_PEN   = 4.0;
    private const RING_R      = 48.0;    // subdial inner hairline
    private const ICON_DY     = -33.0;   // register icon, value and label offsets
    private const ICON_SIZE   = 20.0;    // fits inside the inner ring, clear of the value at 1.4x text
    private const VALUE_DY    = 1.0;
    private const VALUE_MAX_W = 84.0;    // widest value inside the gauge ring, with a margin
    private const AOD_VALUE_MAX_W = 64.0;  // per value in the always-on row
    private const LABEL_DY    = 54.0;    // just below the gauge's bottom opening, clear of its end caps
    private const LABEL_MAX_W = 96.0;    // widest label before it is tightened (BATTERY fits as is)
    private const DATE_Y      = 119.0;
    private const DATE_H      = 44.0;
    private const DATE_PAD    = 12.0;
    private const DATE_GAP    = 8.0;
    private const AOD_DOT_Y   = 27.0;
    private const AOD_ROW_Y   = 329.0;
    private const AOD_STEP    = 5.0;     // always-on shift grid spacing
    private const HALO        = 2.0;     // black margin around the hands

    // Font sizes, design px at the watch's default text size. The Venu 4 is
    // 326 ppi (~13 px per mm), so these are sized for the wrist rather than
    // copied from the design's px. All text follows the watch's Font Scale
    // setting; labels only up to LABEL_SCALE_MAX so they still fit between
    // the registers and the hour indices.
    private const VALUE_PX = 36.0;
    private const LABEL_PX = 24.0;
    private const DAY_PX   = 26.0;
    private const DATE_PX  = 32.0;
    private const AOD_PX   = 26.0;
    private const SCALE_MIN = 0.8;
    private const SCALE_MAX = 1.4;
    private const LABEL_SCALE_MAX = 1.15;

    private const LOW_BATTERY = 20;      // percent, amber + "LOW" label at or below
    private const CALORIE_SCALE = 3000;  // kcal at a full calorie gauge (there is no calorie goal API)
    // Oldest history sample shown when the live value is missing: Body Battery
    // and stress are sampled every few minutes; Pulse Ox mostly overnight, so
    // last night's reading still counts the next day
    private const HISTORY_MAX_AGE  = 2 * 3600;    // s
    private const PULSE_OX_MAX_AGE = 24 * 3600;   // s

    private const MODE_ON  = 0;
    private const MODE_LOW = 1;   // low power: always-on on AMOLED, a minute tick on MIP
    private const MODE_OFF = 2;

    private var _lowPower as Boolean = false;
    // MIP (transflective) screen: always on, no burn-in, 64 colors
    private var _mip as Boolean = false;

    // Main face colors for this screen, set in loadPalette()
    private var _cIvory     as Number = 0;
    private var _cHand      as Number = 0;
    private var _cFacet     as Number = 0;
    private var _cGraphite  as Number = 0;
    private var _cAsh       as Number = 0;
    private var _cAmber     as Number = 0;
    private var _cTickMin   as Number = 0;
    private var _cTick5     as Number = 0;
    private var _cTickHour  as Number = 0;
    private var _cDateEdge  as Number = 0;
    private var _cChampagne as Number = 0;
    private var _accents      as Array<Number> = [] as Array<Number>;
    private var _metricColors as Array<Number> = [] as Array<Number>;

    private var _accent as Number = 0xD4B37A;
    private var _handAccent as Number = 0xD4B37A;   // seconds hand + cap: never ivory-on-ivory
    private var _showSeconds as Boolean = true;

    // Per-frame transform: design px -> screen px (scale + always-on shift)
    private var _k as Float = 1.0;
    private var _ox as Float = 0.0;
    private var _oy as Float = 0.0;

    // Vector fonts (API 4.2+, drawn via drawAngledText); bitmap fallbacks otherwise
    private var _vectorFonts as Boolean = false;
    private var _fontScale as Float = 1.0;
    private var _valueFont as Meridian.Font = Graphics.FONT_SMALL;
    private var _labelFont as Meridian.Font = Graphics.FONT_XTINY;
    private var _labelFontSmall as Meridian.Font = Graphics.FONT_XTINY;   // for labels too wide at full size
    private var _dayFont   as Meridian.Font = Graphics.FONT_XTINY;
    private var _dateFont  as Meridian.Font = Graphics.FONT_TINY;
    private var _aodFont   as Meridian.Font = Graphics.FONT_TINY;
    // Label fonts where there is no vector font: the system's smallest, or
    // bundled bitmap fonts on watches where that is too wide (loadLabelFonts)
    private var _labelBitmap as Meridian.Font = Graphics.FONT_XTINY;
    private var _labelBitmapSmall as Meridian.Font = Graphics.FONT_XTINY;
    // CJK faces at label/weekday size, so translated labels match the Latin ones
    private var _cjkLabelFont as Graphics.VectorFont? = null;
    private var _cjkDayFont   as Graphics.VectorFont? = null;

    // Register labels per metric, from string resources so they follow the
    // watch language
    private var _labels as Array<String> = [] as Array<String>;
    private var _lblLow as String = "LOW";
    private var _decimalSep as String = ".";    // "12.3k" / "12,3k", from the watch language

    // Metric in each slot (left, right, bottom), from settings
    private var _slots as Array<Number> = [0, 1, 2] as Array<Number>;

    // Static parts of the main face (dial, gauge tracks, labels, date window),
    // rendered once and redrawn only when the accent, the date, the text size
    // or the low-battery state changes.
    private var _layer as Graphics.BufferedBitmap? = null;
    private var _layerDirty as Boolean = true;

    // Data, refreshed by updateData() for the metrics on the face. Indexed by
    // metric (Meridian.M_*).
    private var _val  as Array<Number?> = [] as Array<Number?>;   // value shown
    private var _live as Array<Number?> = [] as Array<Number?>;   // pushed by complications
    private var _hist as Array<Number?> = [] as Array<Number?>;   // per-minute history fallback
    private var _goal as Array<Number?> = [] as Array<Number?>;   // step, floor, intensity goals
    private var _stale as Number = -1;           // bit per metric: history due for a re-read
    private var _battLow as Boolean = false;
    private var _minute as Number = -1;          // clock minute of the last refresh
    private var _dayText as String = "";
    private var _numText as String = "";

    function initialize() {
        WatchFace.initialize();
        var n = Meridian.METRIC_COUNT;
        _val  = new Array<Number?>[n];
        _live = new Array<Number?>[n];
        _hist = new Array<Number?>[n];
        _goal = new Array<Number?>[n];
        _labels = [
            WatchUi.loadResource(Rez.Strings.LabelHeartRate) as String,
            WatchUi.loadResource(Rez.Strings.LabelBodyBattery) as String,
            WatchUi.loadResource(Rez.Strings.LabelBattery) as String,
            WatchUi.loadResource(Rez.Strings.LabelStress) as String,
            WatchUi.loadResource(Rez.Strings.LabelSteps) as String,
            WatchUi.loadResource(Rez.Strings.LabelFloors) as String,
            WatchUi.loadResource(Rez.Strings.LabelIntensity) as String,
            WatchUi.loadResource(Rez.Strings.LabelCalories) as String,
            WatchUi.loadResource(Rez.Strings.LabelPulseOx) as String,
            WatchUi.loadResource(Rez.Strings.LabelRespiration) as String,
            WatchUi.loadResource(Rez.Strings.LabelSleep) as String
        ] as Array<String>;
        _lblLow = WatchUi.loadResource(Rez.Strings.LabelBatteryLow) as String;
        _decimalSep = WatchUi.loadResource(Rez.Strings.DecimalSeparator) as String;
        loadLabelFonts();
        _fontScale = readFontScale();
        if (Toybox has :Complications) {
            try {
                Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
            } catch (e) {
                // complications unavailable on this device/firmware
            }
        }
        loadPalette();
        loadSettings();
    }

    // AMOLED watches report that they need burn-in protection; MIP ones don't.
    private function loadPalette() as Void {
        var ds = System.getDeviceSettings();
        _mip = !((ds has :requiresBurnInProtection) && ds.requiresBurnInProtection);
        if (_mip) {
            // Flat white hands (a light facet would only dim them on a
            // reflective screen), grays from the palette's two steps
            _cIvory     = 0xFFFFFF;
            _cHand      = 0xFFFFFF;
            _cFacet     = 0xFFFFFF;
            _cGraphite  = 0x555555;
            _cAsh       = 0xAAAAAA;
            _cAmber     = 0xFFAA00;
            _cTickMin   = 0xAAAAAA;
            _cTick5     = 0xAAAAAA;
            _cTickHour  = 0xFFFFFF;
            _cDateEdge  = 0x555555;
            _cChampagne = MIP_ACCENTS[0] as Number;
            _accents      = MIP_ACCENTS as Array<Number>;
            _metricColors = MIP_METRIC_COLORS as Array<Number>;
        } else {
            _cIvory     = C_IVORY;
            _cHand      = C_HAND;
            _cFacet     = C_FACET;
            _cGraphite  = C_GRAPHITE;
            _cAsh       = C_ASH;
            _cAmber     = C_AMBER;
            _cTickMin   = C_TICK_MIN;
            _cTick5     = C_TICK_5;
            _cTickHour  = C_TICK_HOUR;
            _cDateEdge  = C_DATE_EDGE;
            _cChampagne = C_CHAMPAGNE;
            _accents      = ACCENTS as Array<Number>;
            _metricColors = METRIC_COLORS as Array<Number>;
        }
    }

    function loadSettings() as Void {
        var idx = Application.Properties.getValue("AccentColor");
        if (!(idx instanceof Number) || idx < 0 || idx >= _accents.size()) {
            idx = 0;
        }
        _accent = _accents[idx as Number];
        // An ivory seconds hand would match the ivory hour and minute hands
        _handAccent = (idx == ACCENT_IVORY) ? _cChampagne : _accent;
        var secs = Application.Properties.getValue("ShowSeconds");
        _showSeconds = !(secs instanceof Boolean) || secs;

        _slots = Meridian.slotMetrics();
        subscribeSlots();
        _stale = -1;          // read history for newly chosen metrics right away
        _battLow = false;
        _layerDirty = true;
    }

    // Live updates only for the metrics on the face
    private function subscribeSlots() as Void {
        for (var m = 0; m < Meridian.METRIC_COUNT; m++) {
            _live[m] = null;
        }
        if (!(Toybox has :Complications)) {
            return;
        }
        try {
            Complications.unsubscribeFromAllUpdates();
        } catch (e) {
            // nothing subscribed yet
        }
        for (var i = 0; i < 3; i++) {
            var m = _slots[i];
            if (pushedMetric(m)) {
                var id = new Complications.Id(Meridian.COMPLICATIONS[m] as Complications.Type);
                try {
                    Complications.subscribeToUpdates(id);
                } catch (e) {
                    // not offered on this device/firmware: the register shows "--"
                }
                _live[m] = complicationNumber(id);
            }
        }
    }

    // Metrics whose value comes from a complication push. Heart rate and
    // battery are read directly; the activity counters from ActivityMonitor.
    private function pushedMetric(m as Number) as Boolean {
        return m == Meridian.M_BODY_BATTERY || m == Meridian.M_STRESS || m == Meridian.M_PULSE_OX
            || m == Meridian.M_RESPIRATION || m == Meridian.M_SLEEP;
    }

    function onLayout(dc as Dc) as Void {
        _k = dc.getWidth() / Meridian.SIZE;
        // VectorFont is documented for drawAngledText, so only use vector fonts
        // where that exists (see drawStr).
        _vectorFonts = (Graphics has :getVectorFont) && (dc has :drawAngledText);
        buildFonts();

        // Offscreen layer from the graphics pool; without one, drawStatic()
        // draws straight to the screen every frame.
        _layer = null;
        if (Graphics has :createBufferedBitmap) {
            try {
                _layer = Graphics.createBufferedBitmap({
                    :width => dc.getWidth(),
                    :height => dc.getHeight()
                }).get() as Graphics.BufferedBitmap?;
            } catch (e) {
                _layer = null;
            }
        }
        _layerDirty = true;
    }

    function onShow() as Void {
        refreshFontScale();
    }

    // Re-reads the watch's Font Scale setting; rebuilds fonts when it changed.
    // Called from MeridianApp.onDeviceSettingChanged, onShow and once a minute.
    function refreshFontScale() as Void {
        var s = readFontScale();
        if (s != _fontScale) {
            _fontScale = s;
            buildFonts();
            _layerDirty = true;
        }
    }

    private function readFontScale() as Float {
        var ds = System.getDeviceSettings();
        var s = 1.0;
        if (ds has :fontScale) {
            s = ds.fontScale;
        }
        return (s < SCALE_MIN) ? SCALE_MIN : ((s > SCALE_MAX) ? SCALE_MAX : s);
    }

    // Forerunner 255 family (see monkey.jungle): Roboto Condensed bitmaps
    (:labelFonts)
    private function loadLabelFonts() as Void {
        _labelBitmap = WatchUi.loadResource(Rez.Fonts.LabelFont) as WatchUi.FontResource;
        _labelBitmapSmall = WatchUi.loadResource(Rez.Fonts.LabelFontSmall) as WatchUi.FontResource;
    }

    (:systemLabelFonts)
    private function loadLabelFonts() as Void {
    }

    private function buildFonts() as Void {
        if (!_vectorFonts) {
            _labelFont = _labelBitmap;
            _labelFontSmall = _labelBitmapSmall;
            return;
        }
        var s = _fontScale;
        var ls = (s > LABEL_SCALE_MAX) ? LABEL_SCALE_MAX : s;
        _valueFont = vectorFont(["RobotoRegular"], VALUE_PX * s, Graphics.FONT_SMALL);
        _labelFont = vectorFont(["RobotoCondensedRegular", "RobotoRegular"], LABEL_PX * ls, _labelBitmap);
        _labelFontSmall = vectorFont(["RobotoCondensedRegular", "RobotoRegular"], LABEL_PX * ls * 0.82, _labelBitmapSmall);
        _dayFont   = vectorFont(["RobotoRegular"], DAY_PX * s, Graphics.FONT_XTINY);
        _dateFont  = vectorFont(["RobotoMedium", "RobotoRegular"], DATE_PX * s, Graphics.FONT_TINY);
        _aodFont   = vectorFont(["RobotoRegular"], AOD_PX * s, Graphics.FONT_TINY);

        var cjk = cjkFaces();
        _cjkLabelFont = Graphics.getVectorFont({ :face => cjk, :size => (LABEL_PX * ls * _k + 0.5).toNumber() });
        _cjkDayFont   = Graphics.getVectorFont({ :face => cjk, :size => (DAY_PX * s * _k + 0.5).toNumber() });
    }

    // Device CJK faces, preferring the one for the watch language (kanji take
    // Japanese shapes in Kosugi, Chinese shapes in Noto Sans SC)
    private function cjkFaces() as Array<String> {
        var lang = System.getDeviceSettings().systemLanguage;
        if (lang == System.LANGUAGE_JPN) {
            return ["KosugiRegular", "NotoSansSCMedium"];
        }
        if (lang == System.LANGUAGE_KOR) {
            return ["NanumGothicBold"];
        }
        return ["NotoSansSCMedium", "KosugiRegular"];
    }

    private function vectorFont(faces as Array<String>, designPx as Float, fallback as Meridian.Font) as Meridian.Font {
        var f = Graphics.getVectorFont({ :face => faces, :size => (designPx * _k + 0.5).toNumber() });
        return (f != null) ? f : fallback;
    }

    function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    // Complication pushes for the metrics on the face (see subscribeSlots)
    function onComplicationChanged(id as Complications.Id) as Void {
        var t = id.getType();
        for (var i = 0; i < 3; i++) {
            var m = _slots[i];
            if (pushedMetric(m) && Meridian.COMPLICATIONS[m] == t) {
                _live[m] = complicationNumber(id);
            }
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(C_BLACK, C_BLACK);
        dc.clear();

        var mode = displayMode();
        if (mode == MODE_OFF) {
            return;
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        _k = dc.getWidth() / Meridian.SIZE;
        var clock = System.getClockTime();
        updateData(clock);

        // A MIP screen stays on and can't burn in, so in low power it keeps
        // the full face; it is only redrawn once a minute, so no seconds hand
        if (mode == MODE_LOW && !_mip) {
            drawAlwaysOn(dc, clock);
            return;
        }

        _ox = 0.0;
        _oy = 0.0;
        drawStaticLayer(dc);
        drawSubdialValues(dc);
        drawHands(dc, clock, mode == MODE_ON);
    }

    // Low power when either the sleep callbacks or the system say so: a face
    // (re)started while the screen is already in always-on gets no
    // onEnterSleep. Nothing is drawn while the display is off.
    private function displayMode() as Number {
        var low = _lowPower;
        if (System has :getDisplayMode) {
            var m = System.getDisplayMode();
            if (m == System.DISPLAY_MODE_OFF) {
                return MODE_OFF;
            }
            low = low || (m == System.DISPLAY_MODE_LOW_POWER);
        }
        return low ? MODE_LOW : MODE_ON;
    }

    // =====================================================================
    // Main face
    // =====================================================================

    private function drawStaticLayer(dc as Dc) as Void {
        var layer = _layer;
        if (layer == null) {
            drawStatic(dc);
            return;
        }
        if (_layerDirty) {
            var ldc = layer.getDc();
            ldc.setColor(C_BLACK, C_BLACK);
            ldc.clear();
            if (ldc has :setAntiAlias) {
                ldc.setAntiAlias(true);
            }
            drawStatic(ldc);
            _layerDirty = false;
        }
        dc.drawBitmap(0, 0, layer);
    }

    private function drawStatic(dc as Dc) as Void {
        drawDial(dc);
        for (var i = 0; i < 3; i++) {
            var m = _slots[i];
            // Low battery is spelled out, not only shown in amber
            var low = _battLow && m == Meridian.M_BATTERY;
            drawSubdialFrame(dc, Meridian.SLOT_X[i] as Float, Meridian.SLOT_Y[i] as Float,
                low ? _lblLow : _labels[m], low ? _cAmber : _cAsh);
        }
        drawDateWindow(dc);
    }

    // Minute track, 5-minute marks, hour indices, double accent bar at 12
    private function drawDial(dc as Dc) as Void {
        for (var i = 0; i < 60; i++) {
            var five = (i % 5 == 0);
            dc.setColor(five ? _cTickHour : _cTickMin, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(five ? 3.0 : 1.4));
            radialLine(dc, i * 6.0, 211.0, 219.0);
        }

        // 12 o'clock: two accent bars
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        fillDesignRect(dc, 217.5, 20.0, 6.0, 32.0, 0.0);
        fillDesignRect(dc, 230.5, 20.0, 6.0, 32.0, 0.0);

        // 1..11 o'clock: ivory indices, 7 px wide. They can't grow in length:
        // inward they'd touch the label under the 6 o'clock register, outward
        // the minute track.
        dc.setColor(_cIvory, Graphics.COLOR_TRANSPARENT);
        for (var h = 1; h < 12; h++) {
            fillDesignRect(dc, 223.5, 20.0, 7.0, 30.0, h * 30.0);
        }
        dc.setPenWidth(1);
    }

    // Static part of a register: hairline ring, gauge track, end-of-scale tick, label
    private function drawSubdialFrame(dc as Dc, dx as Float, dy as Float, label as String,
                                      labelColor as Number) as Void {
        var cx = X(dx);
        var cy = Y(dy);

        // The near-black hairline would round to black on MIP; skipped there
        if (!_mip) {
            dc.setColor(C_SUB_RING, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawCircle(cx, cy, RING_R * _k);
        }

        var r = Meridian.SUB_R * _k;
        var p = pen(GAUGE_PEN);
        dc.setPenWidth(p);
        dc.setColor(_cGraphite, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, GAUGE_START, GAUGE_END);
        arcCap(dc, cx, cy, r, GAUGE_END.toFloat(), p / 2.0);

        // The dim track is decorative; this tick marks the end of the scale at
        // 3:1+ (the start always carries the value's colored dot).
        var a = Math.toRadians(GAUGE_END);
        var c = Math.cos(a);
        var s = -Math.sin(a);
        var r0 = r - 5 * _k;
        var r1 = r + 5 * _k;
        dc.setColor(_cTick5, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen(2.0));
        dc.drawLine(cx + r0 * c, cy + r0 * s, cx + r1 * c, cy + r1 * s);
        dc.setPenWidth(1);

        // A label wider than the register (long metric names, translations)
        // loses its letter-spacing first, then drops to the smaller font
        var font = _labelFont;
        var track = LABEL_PX * 0.05 * _k;
        var maxW = LABEL_MAX_W * _k;
        if (trackedWidth(dc, font, _cjkLabelFont, label, track) > maxW) {
            track = 0.0;
            if (trackedWidth(dc, font, _cjkLabelFont, label, track) > maxW) {
                font = _labelFontSmall;
            }
        }
        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        drawTracked(dc, cx, cy + LABEL_DY * _k, font, _cjkLabelFont, label, track);
    }

    private function drawSubdialValues(dc as Dc) as Void {
        for (var i = 0; i < 3; i++) {
            var m = _slots[i];
            var frac = gaugeFraction(m);
            // Watch battery: amber (and the "LOW" label) at 20% or less of the value shown
            var low = _battLow && m == Meridian.M_BATTERY;
            drawSubdialValue(dc, Meridian.SLOT_X[i] as Float, Meridian.SLOT_Y[i] as Float, frac,
                low ? _cAmber : _metricColors[m], m,
                valueText(dc, m, _valueFont, VALUE_MAX_W * _k), low ? _cAmber : _cIvory,
                (m == Meridian.M_BATTERY) ? frac : 0.0);
        }
    }

    // Share of the 270° gauge a metric fills
    private function gaugeFraction(m as Number) as Float {
        var v = _val[m];
        if (v == null) {
            return 0.0;
        }
        if (m == Meridian.M_HEART_RATE) {
            return (v - 40) / 160.0;              // 40-200 bpm
        }
        if (m == Meridian.M_STEPS || m == Meridian.M_FLOORS || m == Meridian.M_INTENSITY) {
            var goal = _goal[m];                  // progress to the user's goal
            return (goal != null && goal > 0) ? v.toFloat() / goal : 0.0;
        }
        if (m == Meridian.M_CALORIES) {
            return v.toFloat() / CALORIE_SCALE;
        }
        if (m == Meridian.M_PULSE_OX) {
            return (v - 70) / 30.0;               // 70-100%
        }
        if (m == Meridian.M_RESPIRATION) {
            return v / 30.0;                      // 0-30 breaths per minute
        }
        return v / 100.0;                         // Body Battery, battery, stress, sleep score
    }

    // Live part of a register: gauge value, icon, value text
    private function drawSubdialValue(dc as Dc, dx as Float, dy as Float, frac as Float, color as Number,
                                      metric as Number, value as String, valueColor as Number,
                                      battFrac as Float) as Void {
        var cx = X(dx);
        var cy = Y(dy);

        drawGaugeValue(dc, cx, cy, Meridian.SUB_R * _k, pen(GAUGE_PEN), frac, color);
        drawIcon(dc, metric, cx, cy + ICON_DY * _k, ICON_SIZE * _k, color, true, battFrac);

        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        drawStr(dc, cx, cy + VALUE_DY * _k, _valueFont, value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Value arc over the track, round caps (a zero value still shows a dot, as in the design)
    private function drawGaugeValue(dc as Dc, cx as Float, cy as Float, r as Float, p as Number,
                                    frac as Float, color as Number) as Void {
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var capR = p / 2.0;

        dc.setPenWidth(p);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var sweep = (270 * frac).toNumber();
        if (sweep >= 1) {
            var end = GAUGE_START - sweep;
            if (end < 0) { end += 360; }
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, GAUGE_START, end);
        }
        arcCap(dc, cx, cy, r, GAUGE_START.toFloat(), capR);
        arcCap(dc, cx, cy, r, GAUGE_START - 270.0 * frac, capR);
        dc.setPenWidth(1);
    }

    private function arcCap(dc as Dc, cx as Float, cy as Float, r as Float, deg as Float, capR as Float) as Void {
        var a = Math.toRadians(deg);
        dc.fillCircle(cx + r * Math.cos(a), cy - r * Math.sin(a), capR);
    }

    // Date window at 12: "THU" (ash, tracked) + "19" (accent), sized to the text
    private function drawDateWindow(dc as Dc) as Void {
        var w = drawDateText(dc, DATE_Y, _dateFont, _accent);
        var bw = w + 2 * DATE_PAD * _k;
        var bh = DATE_H * _k * ((_fontScale > 1.0) ? _fontScale : 1.0);
        dc.setColor(_cDateEdge, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(X(Meridian.C) - bw / 2, Y(DATE_Y) - bh / 2, bw, bh, 6 * _k);
    }

    // Draws the day + date number centered at design y, returns the total width
    private function drawDateText(dc as Dc, dy as Float, numFont as Meridian.Font, numColor as Number) as Float {
        var day = _dayText;
        var num = _numText;
        var track = DAY_PX * 0.18 * _k;
        var dayW = trackedWidth(dc, _dayFont, _cjkDayFont, day, track);
        var gap = DATE_GAP * _k;
        var total = dayW + gap + dc.getTextWidthInPixels(num, numFont);
        var left = X(Meridian.C) - total / 2;
        var cy = Y(dy);

        dc.setColor(_cAsh, Graphics.COLOR_TRANSPARENT);
        drawTracked(dc, left + dayW / 2, cy, _dayFont, _cjkDayFont, day, track);
        dc.setColor(numColor, Graphics.COLOR_TRANSPARENT);
        drawStr(dc, left + dayW + gap, cy, numFont, num,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return total;
    }

    // Faceted hour/minute hands, accent seconds hand with counterweight ring
    // (when the setting is on and the face redraws every second)
    private function drawHands(dc as Dc, clock as System.ClockTime, seconds as Boolean) as Void {
        var h = clock.hour % 12;
        var m = clock.min;
        var s = clock.sec;
        var hourDeg = (h + m / 60.0 + s / 3600.0) * 30.0;
        var minDeg = (m + s / 60.0) * 6.0;

        drawFacetedHand(dc, HOUR_HAND, hourDeg);
        drawFacetedHand(dc, MINUTE_HAND, minDeg);

        if (_showSeconds && seconds) {
            var secDeg = s * 6.0;
            var tail = rot(Meridian.C, 275.0, secDeg);
            var tip = rot(Meridian.C, 27.0, secDeg);
            var ring = rot(Meridian.C, 258.0, secDeg);
            dc.setColor(_handAccent, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(3.0));
            dc.drawLine(tail[0], tail[1], tip[0], tip[1]);
            dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(ring[0], ring[1], 7 * _k);
            dc.setColor(_handAccent, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(ring[0], ring[1], 7 * _k);
        }

        dc.setColor(_handAccent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(Meridian.C), Y(Meridian.C), 9 * _k);
        dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(Meridian.C), Y(Meridian.C), 3 * _k);
        dc.setPenWidth(1);
    }

    // Near-white sword, light facet on the left half, on a black halo. The halo is
    // the design's black keyline drawn under the fill instead of over it (over
    // the fill it aliased into a sawtooth on device); only its outer half
    // shows, and it keeps register digits under a hand from merging into it.
    private function drawFacetedHand(dc as Dc, shape as Array<Float>, deg as Float) as Void {
        var pts = handPoints(shape, deg);
        dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen(HALO * 2));
        outline(dc, pts);
        dc.setPenWidth(1);
        dc.setColor(_cHand, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
        if (_cFacet != _cHand) {
            dc.setColor(_cFacet, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([pts[0], pts[5], pts[4], pts[3]]);   // tip, left shoulder, left base, tail
        }
    }

    // =====================================================================
    // Always-on: dim outlines, few pixels, whole layout shifted each minute
    // =====================================================================
    // Each minute the layout moves to the next of 25 offsets on a 5x5 grid
    // (AOD_STEP apart, within ±2 steps), so no offset repeats for 25 minutes.
    // Consecutive minutes move at least 2 steps on both axes (y can stay put
    // once a day, at midnight) and the direction changes from minute to
    // minute, which spreads wear. A thin stroke that happens to lie along one
    // jump can still overlap itself for that one minute.
    private function drawAlwaysOn(dc as Dc, clock as System.ClockTime) as Void {
        var slot = (clock.hour * 60 + clock.min) % 25;
        var step = AOD_STEP * _k;
        _ox = ((3 * slot) % 5 - 2) * step;
        _oy = ((2 * slot + slot / 5) % 5 - 2) * step;

        // Hour dots, champagne mark at 12
        dc.setColor(C_AOD_DOT, Graphics.COLOR_TRANSPARENT);
        for (var i = 1; i < 12; i++) {
            var p = rot(Meridian.C, AOD_DOT_Y, i * 30.0);
            dc.fillCircle(p[0], p[1], 2 * _k);
        }
        dc.setColor(C_AOD_MARK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(Meridian.C), Y(AOD_DOT_Y), 3 * _k);

        // Date, no window
        drawDateText(dc, DATE_Y, _aodFont, C_AOD_LINE);

        // Metrics row, in the registers' order (left, right, bottom)
        var iconSize = 20 * _k;
        var iconGap = 8 * _k;
        var itemGap = 26 * _k;
        var texts = new Array<String>[3];
        var iconW = new Array<Float>[3];
        var textW = new Array<Number>[3];
        var total = itemGap * 2;
        for (var j = 0; j < 3; j++) {
            var m = _slots[j];
            var pct = (m == Meridian.M_BATTERY || m == Meridian.M_PULSE_OX) && _val[m] != null;
            texts[j] = valueText(dc, m, _aodFont, AOD_VALUE_MAX_W * _k) + (pct ? "%" : "");
            // battery viewBox is 26 wide
            iconW[j] = (m == Meridian.M_BATTERY) ? iconSize * 26 / 24 : iconSize;
            textW[j] = dc.getTextWidthInPixels(texts[j] as String, _aodFont);
            total += (iconW[j] as Float) + iconGap + (textW[j] as Number);
        }
        var x = X(Meridian.C) - total / 2;
        var y = Y(AOD_ROW_Y);
        for (var j = 0; j < 3; j++) {
            // Low watch battery stands out here too (the main face also says "LOW")
            var color = (_battLow && _slots[j] == Meridian.M_BATTERY) ? C_AOD_AMBER : C_ASH;
            drawIcon(dc, _slots[j], x + iconW[j] / 2, y, iconSize, color, false, 0.0);
            x += iconW[j] + iconGap;
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawStr(dc, x, y, _aodFont, texts[j], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += textW[j] + itemGap;
        }

        // Outlined hands, no seconds
        var hourDeg = (clock.hour % 12 + clock.min / 60.0) * 30.0;
        var minDeg = clock.min * 6.0;
        dc.setColor(C_AOD_LINE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen(1.5));
        outline(dc, handPoints(HOUR_HAND, hourDeg));
        outline(dc, handPoints(MINUTE_HAND, minDeg));
        dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(Meridian.C), Y(Meridian.C), 4 * _k);
        dc.setColor(C_AOD_LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(X(Meridian.C), Y(Meridian.C), 4 * _k);
        dc.setPenWidth(1);
    }

    // =====================================================================
    // Icons
    // =====================================================================
    // Icon of a metric; size = rendered px of the 24-unit viewBox height.
    // filled: main face (solid shapes); otherwise always-on (outlines).
    private function drawIcon(dc as Dc, metric as Number, cx as Float, cy as Float, size as Float,
                              color as Number, filled as Boolean, battFrac as Float) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var sc = size / 24.0;
        if (metric == Meridian.M_BATTERY) {
            // viewBox 26x24: body (2,6,19,12) stroke 2, nub (22.5,9.5,2.2,5), level (4.5,8.5,<=14,7)
            var ox = cx - 13 * sc;
            var oy = cy - 12 * sc;
            dc.setPenWidth(pen(2 * sc / _k));
            dc.drawRoundedRectangle(ox + 2 * sc, oy + 6 * sc, 19 * sc, 12 * sc, 2.5 * sc);
            dc.fillRectangle(ox + 22.5 * sc, oy + 9.5 * sc, 2.2 * sc, 5 * sc);
            if (filled && battFrac > 0.0) {
                var f = (battFrac > 1.0) ? 1.0 : battFrac;
                dc.fillRectangle(ox + 4.5 * sc, oy + 8.5 * sc, 14 * f * sc, 7 * sc);
            }
            dc.setPenWidth(1);
            return;
        }
        // Strokes: 3 units on the main face so line icons match the solid
        // ones in weight, 2 units in always-on like the outlines
        var stroke = pen((filled ? 3 : 2) * sc / _k);
        var ops = ICONS[metric] as Array<Array<Float>>;
        for (var o = 0; o < ops.size(); o++) {
            var op = ops[o];
            var kind = op[0].toNumber();
            if (kind == 2) {
                dc.setPenWidth(stroke);
                dc.drawCircle(cx + (op[1] - 12) * sc, cy + (op[2] - 12) * sc, op[3] * sc);
                continue;
            }
            var n = (op.size() - 1) / 2;
            var pts = new Array<Graphics.Point2D>[n];
            for (var i = 0; i < n; i++) {
                pts[i] = [cx + (op[1 + 2 * i] - 12) * sc, cy + (op[2 + 2 * i] - 12) * sc];
            }
            if (kind == 0 && filled) {
                dc.fillPolygon(pts);
            } else {
                dc.setPenWidth(stroke);
                for (var i = 0; i < n - 1; i++) {
                    dc.drawLine(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1]);
                }
                if (kind == 0) {    // close the outline
                    dc.drawLine(pts[n - 1][0], pts[n - 1][1], pts[0][0], pts[0][1]);
                }
            }
        }
        dc.setPenWidth(1);
    }

    // =====================================================================
    // Geometry + text helpers
    // =====================================================================
    private function X(v as Numeric) as Float { return (v * _k + _ox).toFloat(); }
    private function Y(v as Numeric) as Float { return (v * _k + _oy).toFloat(); }

    // Pen width from a design-space stroke width
    private function pen(designW as Float) as Number {
        var p = (designW * _k + 0.5).toNumber();
        return (p < 1) ? 1 : p;
    }

    // Design point rotated clockwise about the center, in screen px
    private function rot(x as Float, y as Float, deg as Float) as Graphics.Point2D {
        var a = Math.toRadians(deg);
        var c = Math.cos(a);
        var s = Math.sin(a);
        var dx = x - Meridian.C;
        var dy = y - Meridian.C;
        return [X(Meridian.C + dx * c - dy * s), Y(Meridian.C + dx * s + dy * c)];
    }

    // Line along a radius at clock angle deg (0 = 12 o'clock), design radii
    private function radialLine(dc as Dc, deg as Float, r0 as Float, r1 as Float) as Void {
        var a = Math.toRadians(deg);
        var sx = Math.sin(a);
        var cy = -Math.cos(a);
        dc.drawLine(X(Meridian.C + r0 * sx), Y(Meridian.C + r0 * cy),
                    X(Meridian.C + r1 * sx), Y(Meridian.C + r1 * cy));
    }

    // Design-space rect, rotated clockwise about the dial center
    private function fillDesignRect(dc as Dc, x as Float, y as Float, w as Float, h as Float, deg as Float) as Void {
        dc.fillPolygon([rot(x, y, deg), rot(x + w, y, deg), rot(x + w, y + h, deg), rot(x, y + h, deg)]);
    }

    // Hand outline in screen px; shape is flat [x0, y0, x1, y1, ...] design px
    private function handPoints(shape as Array<Float>, deg as Float) as Array<Graphics.Point2D> {
        var n = shape.size() / 2;
        var pts = new Array<Graphics.Point2D>[n];
        for (var i = 0; i < n; i++) {
            pts[i] = rot(shape[2 * i], shape[2 * i + 1], deg);
        }
        return pts;
    }

    private function outline(dc as Dc, pts as Array<Graphics.Point2D>) as Void {
        var n = pts.size();
        for (var i = 0; i < n; i++) {
            var a = pts[i];
            var b = pts[(i + 1) % n];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }

    // Vector fonts go through drawAngledText (angle 0), bitmap fonts through drawText.
    // Watches without vector fonts (Venu 2, vivoactive 5...) have no VectorFont
    // class at all, so check it exists before testing against it.
    private function drawStr(dc as Dc, x as Numeric, y as Numeric, font as Meridian.Font,
                             text as String, just as Number) as Void {
        if ((Graphics has :VectorFont) && font instanceof Graphics.VectorFont) {
            dc.drawAngledText(x, y, font, text, just, 0);
        } else {
            dc.drawText(x, y, font, text, just);
        }
    }

    // Letter-spaced text (the design's tracked labels), centered on cx.
    // Text Roboto cannot render is drawn whole and untracked: CJK in the
    // device's CJK vector face at the same size, anything else (Arabic,
    // Hebrew, Thai...) in the system font, which follows the device language
    // and keeps letter shaping and right-to-left order.
    private function drawTracked(dc as Dc, cx as Float, cy as Float, font as Meridian.Font,
                                 cjkFont as Graphics.VectorFont?, text as String, track as Float) as Void {
        if (!isRobotoText(text)) {
            drawStr(dc, cx, cy, scriptFont(text, cjkFont), text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var x = cx - trackedWidth(dc, font, cjkFont, text, track) / 2;
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            drawStr(dc, x, cy, font, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(ch, font) + track;
        }
    }

    // Width of text as drawTracked draws it
    private function trackedWidth(dc as Dc, font as Meridian.Font, cjkFont as Graphics.VectorFont?,
                                  text as String, track as Float) as Float {
        if (!isRobotoText(text)) {
            return dc.getTextWidthInPixels(text, scriptFont(text, cjkFont)).toFloat();
        }
        var chars = text.toCharArray();
        var w = 0.0;
        for (var i = 0; i < chars.size(); i++) {
            w += dc.getTextWidthInPixels(chars[i].toString(), font);
        }
        if (chars.size() > 1) {
            w += track * (chars.size() - 1);
        }
        return w;
    }

    private function scriptFont(text as String, cjkFont as Graphics.VectorFont?) as Meridian.Font {
        return (cjkFont != null && isCjkText(text)) ? cjkFont : Graphics.FONT_XTINY;
    }

    // True when every character is CJK: kana, ideographs, Hangul, CJK punctuation
    private function isCjkText(s as String) as Boolean {
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var cp = chars[i].toNumber();
            var cjk = (cp >= 0x3000 && cp <= 0x30FF) || (cp >= 0x3130 && cp <= 0x318F)
                || (cp >= 0x3400 && cp <= 0x9FFF) || (cp >= 0xAC00 && cp <= 0xD7AF)
                || (cp >= 0xFF00 && cp <= 0xFFEF);
            if (!cjk) {
                return false;
            }
        }
        return chars.size() > 0;
    }

    // True when Roboto has glyphs for every character: Latin (incl. Vietnamese),
    // Greek, Cyrillic.
    private function isRobotoText(s as String) as Boolean {
        var chars = s.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var cp = chars[i].toNumber();
            if (cp >= 0x0500 && (cp < 0x1E00 || cp > 0x1EFF)) {
                return false;
            }
        }
        return true;
    }

    // =====================================================================
    // Data
    // =====================================================================
    // Only the metrics on the face are read. Live heart rate, battery and the
    // ActivityMonitor counters every frame; complication values as they are
    // pushed; history samples, the date and the Font Scale setting at most
    // once a minute.
    private function updateData(clock as System.ClockTime) as Void {
        var minute = clock.hour * 60 + clock.min;
        if (minute != _minute) {
            _minute = minute;
            _stale = -1;
            refreshDate();
            refreshFontScale();
        }

        var info = null as ActivityMonitor.Info?;
        var low = false;
        for (var i = 0; i < 3; i++) {
            var m = _slots[i];
            if (info == null && activityMetric(m)) {
                info = ActivityMonitor.getInfo();
            }
            var v = readMetric(m, info);
            _val[m] = v;
            if (m == Meridian.M_BATTERY && v != null && v <= LOW_BATTERY) {
                low = true;
            }
        }
        if (low != _battLow) {
            _battLow = low;
            _layerDirty = true;   // the battery label is in the static layer
        }
    }

    // Counters read from ActivityMonitor.Info
    private function activityMetric(m as Number) as Boolean {
        return m == Meridian.M_STEPS || m == Meridian.M_FLOORS || m == Meridian.M_INTENSITY
            || m == Meridian.M_CALORIES || m == Meridian.M_RESPIRATION;
    }

    private function readMetric(m as Number, info as ActivityMonitor.Info?) as Number? {
        if (m == Meridian.M_BATTERY) {
            return batteryPercent();
        }
        if (m == Meridian.M_HEART_RATE) {
            var hr = liveHeartRate();
            return (hr != null) ? hr : history(m);
        }
        if (info != null) {
            var a = activityValue(m, info);
            if (a != null && a >= 0) {
                return a;
            }
        }
        var live = inRange(m, _live[m]);
        return (live != null) ? live : history(m);
    }

    // A complication or history value outside the metric's range (a
    // "couldn't measure" code such as -1, or a glitch) counts as no reading
    private function inRange(m as Number, v as Number?) as Number? {
        if (v == null) {
            return null;
        }
        var lo = (m == Meridian.M_PULSE_OX) ? 50 : 0;
        var hi = (m == Meridian.M_RESPIRATION) ? 60 : 100;
        return (v >= lo && v <= hi) ? v : null;
    }

    // Today's counters (intensity minutes: this week), and the goal each
    // gauge fills towards
    private function activityValue(m as Number, info as ActivityMonitor.Info) as Number? {
        if (m == Meridian.M_STEPS) {
            _goal[m] = info.stepGoal;
            return info.steps;
        }
        if (m == Meridian.M_FLOORS && (info has :floorsClimbed)) {
            _goal[m] = info.floorsClimbedGoal;
            return info.floorsClimbed;
        }
        if (m == Meridian.M_INTENSITY && (info has :activeMinutesWeek)) {
            _goal[m] = info.activeMinutesWeekGoal;
            var week = info.activeMinutesWeek;
            return (week != null) ? week.total : null;
        }
        if (m == Meridian.M_CALORIES) {
            return info.calories;
        }
        if (m == Meridian.M_RESPIRATION && (info has :respirationRate)) {
            var r = info.respirationRate;
            return (r != null && r > 0) ? r.toNumber() : null;
        }
        return null;
    }

    // Latest history sample, re-read at most once a minute
    private function history(m as Number) as Number? {
        var bit = 1 << m;
        if ((_stale & bit) != 0) {
            _stale &= ~bit;
            _hist[m] = readHistory(m);
        }
        return _hist[m];
    }

    private function readHistory(m as Number) as Number? {
        if (m == Meridian.M_HEART_RATE) {
            return historyHeartRate();
        }
        if (!(Toybox has :SensorHistory)) {
            return null;
        }
        var opts = { :period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST };
        var v = null as Number?;
        if (m == Meridian.M_BODY_BATTERY && (SensorHistory has :getBodyBatteryHistory)) {
            v = newestSample(SensorHistory.getBodyBatteryHistory(opts), HISTORY_MAX_AGE);
        } else if (m == Meridian.M_STRESS && (SensorHistory has :getStressHistory)) {
            v = newestSample(SensorHistory.getStressHistory(opts), HISTORY_MAX_AGE);
        } else if (m == Meridian.M_PULSE_OX && (SensorHistory has :getOxygenSaturationHistory)) {
            v = newestSample(SensorHistory.getOxygenSaturationHistory(opts), PULSE_OX_MAX_AGE);
        }
        return inRange(m, v);
    }

    // The newest sample's value, or null when there is none or it is older
    // than maxAge seconds (so an old reading never passes for a current one)
    private function newestSample(it as SensorHistory.SensorHistoryIterator, maxAge as Number) as Number? {
        var sample = it.next();
        if (sample == null) {
            return null;
        }
        var when = sample.when;
        if (when != null && Time.now().value() - when.value() > maxAge) {
            return null;
        }
        var d = sample.data;
        return (d != null) ? d.toNumber() : null;
    }

    private function refreshDate() as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var day = info.day_of_week.toString().toUpper();
        var num = info.day.toString();
        if (!day.equals(_dayText) || !num.equals(_numText)) {
            _dayText = day;
            _numText = num;
            _layerDirty = true;
        }
    }

    // A value as precise as fits in maxW px: "8432", else "8.4k", else "8k";
    // 10,000 and up "12.3k", else "12k". "--" when there is no reading.
    private function valueText(dc as Dc, m as Number, font as Meridian.Font, maxW as Float) as String {
        var v = _val[m];
        if (v == null) {
            return "--";
        }
        if (v < 1000) {
            return v.toString();
        }
        var options = (v >= 10000)
            ? [kText(v, true), kText(v, false)]
            : [v.toString(), kText(v, true), kText(v, false)];
        var last = options.size() - 1;
        for (var i = 0; i < last; i++) {
            if (dc.getTextWidthInPixels(options[i], font) <= maxW) {
                return options[i];
            }
        }
        return options[last];
    }

    // Thousands: "12.3k" (one decimal, truncated; "12,3k" in languages that
    // write a decimal comma) or "12k"; 100,000 and up always "123k"
    private function kText(v as Number, decimal as Boolean) as String {
        if (!decimal || v >= 100000) {
            return (v / 1000).toString() + "k";
        }
        var t = v / 100;
        return (t / 10).toString() + _decimalSep + (t % 10).toString() + "k";
    }

    // Rounded once, so the number shown and the low-battery cues agree
    private function batteryPercent() as Number {
        var p = (System.getSystemStats().battery + 0.5).toNumber();
        return (p < 0) ? 0 : ((p > 100) ? 100 : p);
    }

    private function liveHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null) {
            var hr = info.currentHeartRate;
            if (hr != null && hr > 0) {
                return hr;
            }
        }
        return null;
    }

    private function historyHeartRate() as Number? {
        var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
        if (sample != null) {
            var hr = sample.heartRate;
            if (hr != null && hr != ActivityMonitor.INVALID_HR_SAMPLE && hr > 0) {
                return hr;
            }
        }
        return null;
    }

    private function complicationNumber(id as Complications.Id) as Number? {
        try {
            var v = Complications.getComplication(id).value;
            if (v != null && !(v instanceof String)) {
                return (v as Numeric).toNumber();
            }
        } catch (e) {
            // complication unavailable on this device/firmware
        }
        return null;
    }
}
