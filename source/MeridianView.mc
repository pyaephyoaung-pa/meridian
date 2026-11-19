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
// Shared with MeridianDelegate for tap hit-testing.
module Meridian {
    const SIZE   = 454.0;
    const C      = 227.0;    // center
    const SUB_R  = 46.0;     // subdial gauge radius
    const HR_X   = 119.0;  const HR_Y   = 227.0;   // 9 o'clock
    const BB_X   = 335.0;  const BB_Y   = 227.0;   // 3 o'clock
    const BAT_X  = 227.0;  const BAT_Y  = 335.0;   // 6 o'clock
}

class MeridianView extends WatchUi.WatchFace {

    // ---- Palette (see design "States & tokens") ----
    private const C_BLACK     = 0x000000;  // ground, pixels off
    private const C_IVORY     = 0xEDE6D6;  // hands, indices, values
    private const C_BONE      = 0xB5AD9C;  // hand facets
    private const C_GRAPHITE  = 0x2B2925;  // gauge tracks
    private const C_ASH       = 0x8F897D;  // labels
    private const C_ROSE      = 0xE8735E;  // heart rate
    private const C_SKY       = 0x6DB5E3;  // Body Battery
    private const C_SAGE      = 0xA8CF96;  // watch battery
    private const C_AMBER     = 0xF29A45;  // battery at 20% or less
    private const C_TICK_MIN  = 0x4A4740;  // minute ticks
    private const C_TICK_5    = 0xA39C8E;  // 5-minute ticks
    private const C_SUB_RING  = 0x1C1B18;  // subdial inner hairline
    private const C_DATE_EDGE = 0x3A3731;  // date window border
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

    // Hands, design space: [tip, right shoulder, tail, left shoulder]
    private const HOUR_HAND   = [227.0, 120.0, 234.0, 212.0, 227.0, 240.0, 220.0, 212.0];
    private const MINUTE_HAND = [227.0,  44.0, 232.0, 212.0, 227.0, 242.0, 222.0, 212.0];

    private const ICON_HEART = 0;
    private const ICON_BOLT  = 1;
    private const ICON_BATT  = 2;

    private var _lowPower as Boolean = false;
    private var _accent as Number = 0xD4B37A;
    private var _showSeconds as Boolean = true;

    // Per-frame transform: design px -> screen px (scale + always-on shift)
    private var _k as Float = 1.0;
    private var _ox as Float = 0.0;
    private var _oy as Float = 0.0;

    // Vector fonts (API 4.2+, drawn via drawAngledText); bitmap fallbacks otherwise
    private var _valueFont as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_SMALL;
    private var _labelFont as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_XTINY;
    private var _dayFont   as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_XTINY;
    private var _dateFont  as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_TINY;
    private var _aodFont   as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_TINY;
    private var _aodDateFont as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_TINY;

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    function loadSettings() as Void {
        var idx = Application.Properties.getValue("AccentColor");
        if (!(idx instanceof Number) || idx < 0 || idx >= ACCENTS.size()) {
            idx = 0;
        }
        _accent = ACCENTS[idx as Number];
        var secs = Application.Properties.getValue("ShowSeconds");
        _showSeconds = !(secs instanceof Boolean) || secs;
    }

    function onLayout(dc as Dc) as Void {
        var k = dc.getWidth() / Meridian.SIZE;
        // VectorFont is documented for drawAngledText, so only use vector fonts
        // where that exists (see drawStr).
        if ((Graphics has :getVectorFont) && (dc has :drawAngledText)) {
            _valueFont   = vectorFont(["RobotoRegular"], 26 * k, _valueFont);
            _labelFont   = vectorFont(["RobotoRegular"], 8 * k, _labelFont);
            _dayFont     = vectorFont(["RobotoRegular"], 10 * k, _dayFont);
            _dateFont    = vectorFont(["RobotoMedium", "RobotoRegular"], 15 * k, _dateFont);
            _aodFont     = vectorFont(["RobotoRegular"], 15 * k, _aodFont);
            _aodDateFont = vectorFont(["RobotoRegular"], 15 * k, _aodDateFont);
        }
    }

    private function vectorFont(faces as Array<String>, size as Numeric,
                                fallback as Graphics.VectorFont or Graphics.FontDefinition)
                                as Graphics.VectorFont or Graphics.FontDefinition {
        var f = Graphics.getVectorFont({ :face => faces, :size => size.toNumber() });
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

    function onUpdate(dc as Dc) as Void {
        dc.setColor(C_BLACK, C_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        _k = dc.getWidth() / Meridian.SIZE;
        var clock = System.getClockTime();

        if (_lowPower) {
            drawAlwaysOn(dc, clock);
            return;
        }

        _ox = 0.0;
        _oy = 0.0;
        drawDial(dc);
        drawSubdials(dc);
        drawDateWindow(dc);
        drawHands(dc, clock);
    }

    // =====================================================================
    // Main face
    // =====================================================================

    // Minute track, 5-minute marks, hour indices, double accent bar at 12
    private function drawDial(dc as Dc) as Void {
        for (var i = 0; i < 60; i++) {
            var five = (i % 5 == 0);
            dc.setColor(five ? C_TICK_5 : C_TICK_MIN, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(five ? 3.0 : 1.4));
            radialLine(dc, i * 6.0, 211.0, 219.0);
        }

        // 12 o'clock: two accent bars
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        fillDesignRect(dc, 219.5, 20.0, 5.0, 32.0, 0.0);
        fillDesignRect(dc, 229.5, 20.0, 5.0, 32.0, 0.0);

        // 1..11 o'clock: ivory indices
        dc.setColor(C_IVORY, Graphics.COLOR_TRANSPARENT);
        for (var h = 1; h < 12; h++) {
            fillDesignRect(dc, 224.5, 20.0, 5.0, 30.0, h * 30.0);
        }
        dc.setPenWidth(1);
    }

    private function drawSubdials(dc as Dc) as Void {
        // Heart rate: arc spans 40-200 bpm
        var hr = getHeartRate();
        var hrFrac = (hr != null) ? (hr - 40) / 160.0 : 0.0;
        drawSubdial(dc, Meridian.HR_X, Meridian.HR_Y, hrFrac, C_ROSE,
            ICON_HEART, C_ROSE, (hr != null && hr > 0) ? hr.toString() : "--", C_IVORY, "BPM", 0.0);

        // Body Battery: 0-100
        var bb = getBodyBattery();
        drawSubdial(dc, Meridian.BB_X, Meridian.BB_Y, (bb != null) ? bb / 100.0 : 0.0, C_SKY,
            ICON_BOLT, C_SKY, (bb != null) ? bb.toString() : "--", C_IVORY, "BODY BATT", 0.0);

        // Watch battery: 0-100%, amber at 20% or less
        var batt = System.getSystemStats().battery;
        var low = batt <= 20;
        var battColor = low ? C_AMBER : C_SAGE;
        drawSubdial(dc, Meridian.BAT_X, Meridian.BAT_Y, batt / 100.0, battColor,
            ICON_BATT, battColor, batt.format("%d"), low ? C_AMBER : C_IVORY, "BATTERY", batt / 100.0);
    }

    // One register: hairline ring, 270° gauge, icon, value, label
    private function drawSubdial(dc as Dc, dx as Float, dy as Float, frac as Float, gaugeColor as Number,
                                 icon as Number, iconColor as Number, value as String, valueColor as Number,
                                 label as String, battFrac as Float) as Void {
        var cx = X(dx);
        var cy = Y(dy);

        dc.setColor(C_SUB_RING, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, 38 * _k);

        drawGauge(dc, cx, cy, Meridian.SUB_R * _k, pen(3.0), frac, gaugeColor);

        drawIcon(dc, icon, cx, cy - 25 * _k, 12 * _k, iconColor, true, battFrac);

        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        drawStr(dc, cx, cy, _valueFont, value, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(C_ASH, Graphics.COLOR_TRANSPARENT);
        drawSpaced(dc, cx, cy + 25 * _k, _labelFont, label, 8 * 0.16 * _k);
    }

    // 270° gauge opening at the bottom: starts at 7:30, runs clockwise to 4:30
    private function drawGauge(dc as Dc, cx as Float, cy as Float, r as Float, p as Number,
                               frac as Float, color as Number) as Void {
        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var start = 225;
        var capR = p / 2.0;

        dc.setPenWidth(p);
        dc.setColor(C_GRAPHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, 315);
        arcCap(dc, cx, cy, r, 315.0, capR);

        // Value arc, round caps (a zero value still shows a dot, as in the design)
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var sweep = (270 * frac).toNumber();
        if (sweep >= 1) {
            var end = start - sweep;
            if (end < 0) { end += 360; }
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, end);
        }
        arcCap(dc, cx, cy, r, start.toFloat(), capR);
        arcCap(dc, cx, cy, r, start - 270.0 * frac, capR);
        dc.setPenWidth(1);
    }

    private function arcCap(dc as Dc, cx as Float, cy as Float, r as Float, deg as Float, capR as Float) as Void {
        var a = Math.toRadians(deg);
        dc.fillCircle(cx + r * Math.cos(a), cy - r * Math.sin(a), capR);
    }

    // Date window at 12: "THU" (ash, tracked) + "19" (accent)
    private function drawDateWindow(dc as Dc) as Void {
        dc.setColor(C_DATE_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(X(189.0), Y(105.0), 76 * _k, 28 * _k, 6 * _k);
        drawDateText(dc, 119.0, _dateFont, _accent);
    }

    private function drawDateText(dc as Dc, dy as Float,
                                  numFont as Graphics.VectorFont or Graphics.FontDefinition,
                                  numColor as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var day = info.day_of_week.toString().toUpper();
        var num = info.day.toString();
        var track = 10 * 0.18 * _k;
        var gap = 8 * _k;
        var dayW = spacedWidth(dc, _dayFont, day, track);
        var numW = dc.getTextWidthInPixels(num, numFont);
        var left = X(Meridian.C) - (dayW + gap + numW) / 2;
        var cy = Y(dy);

        dc.setColor(C_ASH, Graphics.COLOR_TRANSPARENT);
        drawSpaced(dc, left + dayW / 2, cy, _dayFont, day, track);
        dc.setColor(numColor, Graphics.COLOR_TRANSPARENT);
        drawStr(dc, left + dayW + gap, cy, numFont, num,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
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
            var tail = rot(227.0, 270.0, secDeg);
            var tip = rot(227.0, 32.0, secDeg);
            var ring = rot(227.0, 256.0, secDeg);
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(pen(1.6));
            dc.drawLine(tail[0], tail[1], tip[0], tip[1]);
            dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(ring[0], ring[1], 5 * _k);
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(ring[0], ring[1], 5 * _k);
        }

        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(Meridian.C), Y(Meridian.C), 6.5 * _k);
        dc.setColor(C_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(Meridian.C), Y(Meridian.C), 2.2 * _k);
        dc.setPenWidth(1);
    }

    // Ivory diamond, bone facet on the left half. (The design's 1.2 px black
    // keyline is left out: drawn as lines over the fill it aliases into a
    // sawtooth edge on device, and the facets already separate the hands.)
    private function drawFacetedHand(dc as Dc, shape as Array<Float>, deg as Float) as Void {
        var pts = handPoints(shape, deg);
        dc.setColor(C_IVORY, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
        dc.setColor(C_BONE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pts[0], pts[3], pts[2]]);
    }

    // =====================================================================
    // Always-on: dim outlines, few pixels, whole layout shifted each minute
    // =====================================================================
    // AMOLED rule: no pixel may stay lit for more than ~3 minutes. Everything
    // jumps diagonally each minute (both axes flip, so no 1-4 px stroke lands on
    // itself in consecutive minutes) and drifts over a 30-minute cycle.
    private function drawAlwaysOn(dc as Dc, clock as System.ClockTime) as Void {
        var step = 5 * _k;
        var flip = (clock.min % 2 == 0) ? -1 : 1;
        _ox = flip * step + ((clock.min / 2) % 5 - 2) * step / 2;
        _oy = flip * step + ((clock.min / 10) % 3 - 1) * step / 2;

        // Hour dots, champagne mark at 12
        dc.setColor(C_AOD_DOT, Graphics.COLOR_TRANSPARENT);
        for (var i = 1; i < 12; i++) {
            var p = rot(227.0, 27.0, i * 30.0);
            dc.fillCircle(p[0], p[1], 2 * _k);
        }
        dc.setColor(C_AOD_MARK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(X(227.0), Y(27.0), 3 * _k);

        // Date, no window
        drawDateText(dc, 119.0, _aodDateFont, C_AOD_LINE);

        // Metrics row: heart · Body Battery · battery %
        var hr = getHeartRate();
        var bb = getBodyBattery();
        var batt = System.getSystemStats().battery;
        var texts = [
            (hr != null && hr > 0) ? hr.toString() : "--",
            (bb != null) ? bb.toString() : "--",
            batt.format("%d") + "%"
        ];
        var icons = [ICON_HEART, ICON_BOLT, ICON_BATT];
        var iconW = [11 * _k, 11 * _k, 13 * _k];
        var iconGap = 6 * _k;
        var itemGap = 18 * _k;
        var total = itemGap * 2;
        for (var j = 0; j < 3; j++) {
            total += iconW[j] + iconGap + dc.getTextWidthInPixels(texts[j], _aodFont);
        }
        var x = X(Meridian.C) - total / 2;
        var y = Y(329.0);
        for (var j = 0; j < 3; j++) {
            drawIcon(dc, icons[j], x + iconW[j] / 2, y, 11 * _k, C_ASH, false, 0.0);
            x += iconW[j] + iconGap;
            dc.setColor(C_ASH, Graphics.COLOR_TRANSPARENT);
            drawStr(dc, x, y, _aodFont, texts[j], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(texts[j], _aodFont) + itemGap;
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
        var pts = new Array<[Numeric, Numeric]>[n];
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
    private function X(v as Float) as Float { return v * _k + _ox; }
    private function Y(v as Float) as Float { return v * _k + _oy; }

    // Pen width from a design-space stroke width
    private function pen(designW as Float) as Number {
        var p = (designW * _k + 0.5).toNumber();
        return (p < 1) ? 1 : p;
    }

    // Design point rotated clockwise about the center, in screen px
    private function rot(x as Float, y as Float, deg as Float) as [Float, Float] {
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

    private function handPoints(shape as Array<Float>, deg as Float) as Array<[Float, Float]> {
        return [
            rot(shape[0], shape[1], deg),
            rot(shape[2], shape[3], deg),
            rot(shape[4], shape[5], deg),
            rot(shape[6], shape[7], deg)
        ];
    }

    private function outline(dc as Dc, pts as Array<[Numeric, Numeric]>) as Void {
        var n = pts.size();
        for (var i = 0; i < n; i++) {
            var a = pts[i];
            var b = pts[(i + 1) % n];
            dc.drawLine(a[0], a[1], b[0], b[1]);
        }
    }

    // Vector fonts go through drawAngledText (angle 0), bitmap fonts through drawText
    private function drawStr(dc as Dc, x as Numeric, y as Numeric,
                             font as Graphics.VectorFont or Graphics.FontDefinition,
                             text as String, just as Number) as Void {
        if (font instanceof Graphics.VectorFont) {
            dc.drawAngledText(x, y, font, text, just, 0);
        } else {
            dc.drawText(x, y, font, text, just);
        }
    }

    // Letter-spaced text (the design's tracked labels), centered on cx
    private function drawSpaced(dc as Dc, cx as Float, cy as Float,
                                font as Graphics.VectorFont or Graphics.FontDefinition,
                                text as String, track as Float) as Void {
        var x = cx - spacedWidth(dc, font, text, track) / 2;
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            drawStr(dc, x, cy, font, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(ch, font) + track;
        }
    }

    private function spacedWidth(dc as Dc, font as Graphics.VectorFont or Graphics.FontDefinition,
                                 text as String, track as Float) as Float {
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

    // =====================================================================
    // Data
    // =====================================================================
    private function getHeartRate() as Number or Null {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        var it = ActivityMonitor.getHeartRateHistory(1, true);
        var sample = it.next();
        if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
            return sample.heartRate;
        }
        return null;
    }

    // Live value from the Body Battery complication; falls back to the latest
    // SensorHistory sample. Null when neither source has data.
    private function getBodyBattery() as Number or Null {
        if (Toybox has :Complications) {
            try {
                var c = Complications.getComplication(
                    new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY));
                var v = c.value;
                if (v instanceof Number || v instanceof Float || v instanceof Double) {
                    return v.toNumber();
                }
            } catch (e) {
                // complication unavailable on this device/firmware
            }
        }
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var it = SensorHistory.getBodyBatteryHistory({
                :period => 1,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            var sample = it.next();
            if (sample != null && sample.data != null) {
                return sample.data.toNumber();
            }
        }
        return null;
    }
}
