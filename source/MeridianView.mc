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

// Meridian — three-register analog face for Venu 4.
// Heart rate at 9, Body Battery at 3, watch battery at 6, date at 12.
//
// All geometry is written in the design's 454 px space (Venu 4 45mm) and
// scaled by w/454 at draw time, so the 41mm (390 px) gets the same layout.
// Shared with MeridianDelegate for press hit-testing.
module Meridian {
    const SIZE   = 454.0;
    const C      = 227.0;    // center
    const SUB_R  = 58.0;     // subdial gauge radius
    const HR_X   = 119.0;  const HR_Y   = 227.0;   // 9 o'clock
    const BB_X   = 335.0;  const BB_Y   = 227.0;   // 3 o'clock
    const BAT_X  = 227.0;  const BAT_Y  = 335.0;   // 6 o'clock

    typedef Font as Graphics.VectorFont or Graphics.FontDefinition;
}

class MeridianView extends WatchUi.WatchFace {

    // ---- Palette (see design "States & tokens") ----
    // Contrast on black: text >= 6:1; graphics needed to read the face >= 3:1.
    private const C_BLACK     = 0x000000;  // ground, pixels off
    private const C_IVORY     = 0xEDE6D6;  // indices, values
    private const C_HAND      = 0xFFF8EC;  // hour + minute hands, brighter than the indices
    private const C_FACET     = 0xD9CFBC;  // hand facets, light so the whole hand reads bright
    private const C_GRAPHITE  = 0x2B2925;  // gauge tracks (decorative; the scale ends are marked)
    private const C_ASH       = 0x8F897D;  // labels
    private const C_ROSE      = 0xE8735E;  // heart rate
    private const C_SKY       = 0x6DB5E3;  // Body Battery
    private const C_SAGE      = 0xA8CF96;  // watch battery
    private const C_AMBER     = 0xF29A45;  // battery at 20% or less
    private const C_TICK_MIN  = 0x8A8478;  // minute ticks (5.7:1; 3:1 was near-invisible on device)
    private const C_TICK_5    = 0xA39C8E;  // gauge end-of-scale tick
    private const C_TICK_HOUR = 0xD6CEBD;  // 5-minute marks on the minute track
    private const C_SUB_RING  = 0x1C1B18;  // subdial inner hairline (decorative)
    private const C_DATE_EDGE = 0x3A3731;  // date window border (decorative)
    private const C_CHAMPAGNE = 0xD4B37A;
    // Always-on
    private const C_AOD_DOT   = 0x6B665C;
    private const C_AOD_MARK  = 0x9C8559;
    private const C_AOD_LINE  = 0xA39C8E;

    // Accent (setting AccentColor): Champagne, Ivory, Sky, Rose
    private const ACCENTS = [0xD4B37A, 0xEDE6D6, 0x6DB5E3, 0xE8735E];

    // Icons in a 24-unit viewBox (heart sampled from the design's SVG path)
    private const HEART = [
        12.0, 20.5, 10.8, 19.7, 8.0, 17.6, 4.9, 14.7, 2.7, 11.3, 2.3, 8.8,
        3.0, 6.6, 4.7, 5.1, 7.0, 4.5, 8.4, 4.7, 9.7, 5.3, 10.9, 6.2,
        12.0, 7.4, 13.1, 6.2, 14.3, 5.3, 15.6, 4.7, 17.0, 4.5, 19.3, 5.1,
        21.0, 6.6, 21.7, 8.8, 21.3, 11.3, 19.1, 14.7, 16.0, 17.6, 13.2, 19.7
    ];
    private const BOLT = [13.5, 2.0, 5.0, 13.5, 11.2, 13.5, 10.0, 22.0, 18.5, 10.5, 12.3, 10.5];

    // Sword hands, design space, clockwise from the tip:
    // [tip, right shoulder, right base, tail, left base, left shoulder].
    // Hour 22 px wide reaching r130; minute 16 px wide reaching the minute track.
    private const HOUR_HAND   = [227.0,  97.0, 238.0, 134.0, 234.5, 212.0, 227.0, 249.0, 219.5, 212.0, 216.0, 134.0];
    private const MINUTE_HAND = [227.0,  23.0, 235.0,  66.0, 233.0, 212.0, 227.0, 251.0, 221.0, 212.0, 219.0,  66.0];

    private const ICON_HEART = 0;
    private const ICON_BOLT  = 1;
    private const ICON_BATT  = 2;

    // ---- Layout, design px ----
    // Gauge: 270° opening at the bottom. Dc.drawArc degrees (0 = 3 o'clock,
    // counter-clockwise), so it starts at 7:30 and runs clockwise to 4:30.
    private const GAUGE_START = 225;
    private const GAUGE_END   = 315;
    private const GAUGE_PEN   = 4.0;
    private const RING_R      = 48.0;    // subdial inner hairline
    private const ICON_DY     = -33.0;   // register icon, value and label offsets
    private const ICON_SIZE   = 16.0;
    private const VALUE_DY    = 1.0;
    private const LABEL_DY    = 54.0;    // just below the gauge's bottom opening, clear of its end caps
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

    private const MODE_ON  = 0;
    private const MODE_AOD = 1;
    private const MODE_OFF = 2;

    private var _lowPower as Boolean = false;
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
    private var _dayFont   as Meridian.Font = Graphics.FONT_XTINY;
    private var _dateFont  as Meridian.Font = Graphics.FONT_TINY;
    private var _aodFont   as Meridian.Font = Graphics.FONT_TINY;
    // CJK faces at label/weekday size, so translated labels match the Latin ones
    private var _cjkLabelFont as Graphics.VectorFont? = null;
    private var _cjkDayFont   as Graphics.VectorFont? = null;

    // Register labels, from string resources so they follow the watch language
    private var _lblHr as String = "BPM";
    private var _lblBb as String = "ENERGY";
    private var _lblBatt as String = "BATTERY";
    private var _lblLow as String = "LOW";

    // Static parts of the main face (dial, gauge tracks, labels, date window),
    // rendered once and redrawn only when the accent, the date, the text size
    // or the low-battery state changes.
    private var _layer as Graphics.BufferedBitmap? = null;
    private var _layerDirty as Boolean = true;

    // Data, refreshed by updateData()
    private var _hr as Number? = null;
    private var _bb as Number? = null;
    private var _batt as Number = 0;
    private var _battLow as Boolean = false;
    private var _minute as Number = -1;          // clock minute of the last refresh
    private var _hrHistory as Number? = null;    // per-minute fallbacks
    private var _hrStale as Boolean = true;
    private var _bbHistory as Number? = null;
    private var _bbStale as Boolean = true;
    private var _bbLive as Number? = null;       // pushed by the complication callback
    private var _dayText as String = "";
    private var _numText as String = "";

    function initialize() {
        WatchFace.initialize();
        loadSettings();
        _lblHr   = WatchUi.loadResource(Rez.Strings.LabelHeartRate) as String;
        _lblBb   = WatchUi.loadResource(Rez.Strings.LabelBodyBattery) as String;
        _lblBatt = WatchUi.loadResource(Rez.Strings.LabelBattery) as String;
        _lblLow  = WatchUi.loadResource(Rez.Strings.LabelBatteryLow) as String;
        _fontScale = readFontScale();
        if (Toybox has :Complications) {
            var id = new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY);
            try {
                Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
                Complications.subscribeToUpdates(id);
            } catch (e) {
                // complication unavailable on this device/firmware
            }
            _bbLive = complicationNumber(id);
        }
    }

    function loadSettings() as Void {
        var idx = Application.Properties.getValue("AccentColor");
        if (!(idx instanceof Number) || idx < 0 || idx >= ACCENTS.size()) {
            idx = 0;
        }
        _accent = ACCENTS[idx as Number];
        // An ivory seconds hand would match the ivory hour and minute hands
        _handAccent = (_accent == C_IVORY) ? C_CHAMPAGNE : _accent;
        var secs = Application.Properties.getValue("ShowSeconds");
        _showSeconds = !(secs instanceof Boolean) || secs;
        _layerDirty = true;
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

    private function buildFonts() as Void {
        if (!_vectorFonts) {
            return;
        }
        var s = _fontScale;
        var ls = (s > LABEL_SCALE_MAX) ? LABEL_SCALE_MAX : s;
        _valueFont = vectorFont(["RobotoRegular"], VALUE_PX * s, Graphics.FONT_SMALL);
        _labelFont = vectorFont(["RobotoCondensedRegular", "RobotoRegular"], LABEL_PX * ls, Graphics.FONT_XTINY);
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

    // Body Battery complication pushes (subscribed in initialize)
    function onComplicationChanged(id as Complications.Id) as Void {
        if (id.getType() == Complications.COMPLICATION_TYPE_BODY_BATTERY) {
            _bbLive = complicationNumber(id);
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

        if (mode == MODE_AOD) {
            drawAlwaysOn(dc, clock);
            return;
        }

        _ox = 0.0;
        _oy = 0.0;
        drawStaticLayer(dc);
        drawSubdialValues(dc);
        drawHands(dc, clock);
    }

    // Always-on when either the sleep callbacks or the system say so: a face
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
        return low ? MODE_AOD : MODE_ON;
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
        drawSubdialFrame(dc, Meridian.HR_X, Meridian.HR_Y, _lblHr, C_ASH);
        drawSubdialFrame(dc, Meridian.BB_X, Meridian.BB_Y, _lblBb, C_ASH);
        // Low battery is spelled out, not only shown in amber
        drawSubdialFrame(dc, Meridian.BAT_X, Meridian.BAT_Y,
            _battLow ? _lblLow : _lblBatt, _battLow ? C_AMBER : C_ASH);
        drawDateWindow(dc);
    }

    // Minute track, 5-minute marks, hour indices, double accent bar at 12
    private function drawDial(dc as Dc) as Void {
        for (var i = 0; i < 60; i++) {
            var five = (i % 5 == 0);
            dc.setColor(five ? C_TICK_HOUR : C_TICK_MIN, Graphics.COLOR_TRANSPARENT);
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
        dc.setColor(C_IVORY, Graphics.COLOR_TRANSPARENT);
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

        dc.setColor(C_SUB_RING, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, RING_R * _k);

        var r = Meridian.SUB_R * _k;
        var p = pen(GAUGE_PEN);
        dc.setPenWidth(p);
        dc.setColor(C_GRAPHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, GAUGE_START, GAUGE_END);
        arcCap(dc, cx, cy, r, GAUGE_END.toFloat(), p / 2.0);

        // The dim track is decorative; this tick marks the end of the scale at
        // 3:1+ (the start always carries the value's colored dot).
        var a = Math.toRadians(GAUGE_END);
        var c = Math.cos(a);
        var s = -Math.sin(a);
        var r0 = r - 5 * _k;
        var r1 = r + 5 * _k;
        dc.setColor(C_TICK_5, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen(2.0));
        dc.drawLine(cx + r0 * c, cy + r0 * s, cx + r1 * c, cy + r1 * s);
        dc.setPenWidth(1);

        dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
        drawTracked(dc, cx, cy + LABEL_DY * _k, _labelFont, _cjkLabelFont, label, LABEL_PX * 0.05 * _k);
    }

    private function drawSubdialValues(dc as Dc) as Void {
        // Heart rate: arc spans 40-200 bpm
        var hr = _hr;
        drawSubdialValue(dc, Meridian.HR_X, Meridian.HR_Y, (hr != null) ? (hr - 40) / 160.0 : 0.0,
            C_ROSE, ICON_HEART, metricText(hr), C_IVORY, 0.0);

        // Body Battery: 0-100
        var bb = _bb;
        drawSubdialValue(dc, Meridian.BB_X, Meridian.BB_Y, (bb != null) ? bb / 100.0 : 0.0,
            C_SKY, ICON_BOLT, metricText(bb), C_IVORY, 0.0);

        // Watch battery: 0-100%, amber (and the "LOW" label) at 20% or less of the value shown
        var battFrac = _batt / 100.0;
        drawSubdialValue(dc, Meridian.BAT_X, Meridian.BAT_Y, battFrac, _battLow ? C_AMBER : C_SAGE,
            ICON_BATT, _batt.toString(), _battLow ? C_AMBER : C_IVORY, battFrac);
    }

    // Live part of a register: gauge value, icon, value text
    private function drawSubdialValue(dc as Dc, dx as Float, dy as Float, frac as Float, color as Number,
                                      icon as Number, value as String, valueColor as Number,
                                      battFrac as Float) as Void {
        var cx = X(dx);
        var cy = Y(dy);

        drawGaugeValue(dc, cx, cy, Meridian.SUB_R * _k, pen(GAUGE_PEN), frac, color);
        drawIcon(dc, icon, cx, cy + ICON_DY * _k, ICON_SIZE * _k, color, true, battFrac);

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
        dc.setColor(C_DATE_EDGE, Graphics.COLOR_TRANSPARENT);
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

        dc.setColor(C_ASH, Graphics.COLOR_TRANSPARENT);
        drawTracked(dc, left + dayW / 2, cy, _dayFont, _cjkDayFont, day, track);
        dc.setColor(numColor, Graphics.COLOR_TRANSPARENT);
        drawStr(dc, left + dayW + gap, cy, numFont, num,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return total;
    }

    // Faceted hour/minute hands, accent seconds hand with counterweight ring
    private function drawHands(dc as Dc, clock as System.ClockTime) as Void {
        var h = clock.hour % 12;
        var m = clock.min;
        var s = clock.sec;
        var hourDeg = (h + m / 60.0 + s / 3600.0) * 30.0;
        var minDeg = (m + s / 60.0) * 6.0;

        drawFacetedHand(dc, HOUR_HAND, hourDeg);
        drawFacetedHand(dc, MINUTE_HAND, minDeg);

        if (_showSeconds) {
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
        dc.setColor(C_HAND, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
        dc.setColor(C_FACET, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pts[0], pts[5], pts[4], pts[3]]);   // tip, left shoulder, left base, tail
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

        // Metrics row: heart · Body Battery · battery %
        var texts = [metricText(_hr), metricText(_bb), _batt.toString() + "%"];
        var icons = [ICON_HEART, ICON_BOLT, ICON_BATT];
        var iconSize = 20 * _k;
        var iconW = [iconSize, iconSize, iconSize * 26 / 24];   // battery viewBox is 26 wide
        var iconGap = 8 * _k;
        var itemGap = 26 * _k;
        var textW = new Array<Number>[3];
        var total = itemGap * 2;
        for (var j = 0; j < 3; j++) {
            textW[j] = dc.getTextWidthInPixels(texts[j], _aodFont);
            total += iconW[j] + iconGap + textW[j];
        }
        var x = X(Meridian.C) - total / 2;
        var y = Y(AOD_ROW_Y);
        for (var j = 0; j < 3; j++) {
            drawIcon(dc, icons[j], x + iconW[j] / 2, y, iconSize, C_ASH, false, 0.0);
            x += iconW[j] + iconGap;
            dc.setColor(C_ASH, Graphics.COLOR_TRANSPARENT);
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
    // size = rendered px of the 24-unit viewBox height
    private function drawIcon(dc as Dc, kind as Number, cx as Float, cy as Float, size as Float,
                              color as Number, filled as Boolean, battFrac as Float) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var sc = size / 24.0;
        if (kind == ICON_BATT) {
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
        var src = (kind == ICON_HEART) ? HEART : BOLT;
        var n = src.size() / 2;
        var pts = new Array<Graphics.Point2D>[n];
        for (var i = 0; i < n; i++) {
            pts[i] = [cx + (src[2 * i] - 12) * sc, cy + (src[2 * i + 1] - 12) * sc];
        }
        if (filled) {
            dc.fillPolygon(pts);
        } else {
            dc.setPenWidth(pen(2 * sc / _k));
            outline(dc, pts);
            dc.setPenWidth(1);
        }
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

    // Vector fonts go through drawAngledText (angle 0), bitmap fonts through drawText
    private function drawStr(dc as Dc, x as Numeric, y as Numeric, font as Meridian.Font,
                             text as String, just as Number) as Void {
        if (font instanceof Graphics.VectorFont) {
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
    // Live heart rate and battery every frame; history samples, the date and
    // the Font Scale setting at most once a minute; Body Battery as the
    // complication pushes it.
    private function updateData(clock as System.ClockTime) as Void {
        var minute = clock.hour * 60 + clock.min;
        if (minute != _minute) {
            _minute = minute;
            _hrStale = true;
            _bbStale = true;
            refreshDate();
            refreshFontScale();
        }

        var hr = liveHeartRate();
        if (hr == null) {
            if (_hrStale) {
                _hrHistory = historyHeartRate();
                _hrStale = false;
            }
            hr = _hrHistory;
        }
        _hr = hr;

        var bb = _bbLive;
        if (bb == null) {
            if (_bbStale) {
                _bbHistory = historyBodyBattery();
                _bbStale = false;
            }
            bb = _bbHistory;
        }
        _bb = bb;

        _batt = batteryPercent();
        var low = _batt <= LOW_BATTERY;
        if (low != _battLow) {
            _battLow = low;
            _layerDirty = true;   // the battery label is in the static layer
        }
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

    // "--" when there is no reading
    private function metricText(v as Number?) as String {
        return (v != null) ? v.toString() : "--";
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

    private function historyBodyBattery() as Number? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var sample = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            }).next();
            if (sample != null) {
                var d = sample.data;
                if (d != null) {
                    return d.toNumber();
                }
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
