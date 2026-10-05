using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Application;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.Math;

class HomePowerFaceView extends WatchUi.WatchFace {
    // Same brand palette as the companion watch app
    // (h0me-p0wer-garmin/source/HomePowerView.mc) - solar green, grid
    // orange, battery violet, home neutral off-white.
    const SOLAR_COLOR = 0x5FCE80;
    const BRAND_ORANGE = 0xF7A44F;
    const BATTERY_VIOLET = 0xC084FC;
    const HOME_COLOR = 0xE8ECEF;

    // Dimmed shades each inner-ring segment (and momentary readout) sits
    // at while its source isn't currently active - the pulse (full
    // color, breathing via lerpColor) is what marks the one that IS.
    const SOLAR_DIM = 0x1F3D28;
    const GRID_DIM = 0x4A3018;
    const BATTERY_DIM = 0x3A2550;
    const HOME_DIM = 0x55595C;

    // Today's three home-consumption sources (same fields the companion
    // app's List/Today page already uses - no backend changes needed)
    // plus the total they sum to, cached from the background fetch.
    var _homeToday = 0.0;
    var _pvDirectToday = 0.0;
    var _batteryOutToday = 0.0;
    var _gridToday = 0.0;

    // Live instantaneous values (not today's totals) - just enough to
    // tell which source is actively flowing right now (2026, user
    // request: "try to pulse which source is used in the moment").
    var _liveHome = 0.0;
    var _liveSolar = 0.0;
    var _liveGrid = 0.0;
    var _liveBatteryPower = 0.0;

    // Pulse animation - only ticks while actively being looked at (same
    // reasoning as the companion app's _pulseTimer): a continuously
    // running Timer would defeat the point of Background-based refresh
    // elsewhere on this face. Outside that window the system still
    // redraws the face once a minute on its own (2026, user request:
    // "make the update every minute") - that's the platform's default
    // watch-face behavior, nothing extra needed for it.
    var _pulseTimer;
    var _pulsePhase = 0.0;
    const PULSE_TICK_MS = 250;
    const PULSE_STEP = 0.5;

    function initialize() {
        WatchFace.initialize();
        _pulseTimer = new Timer.Timer();
    }

    function onLayout(dc) {
    }

    function onShow() {
        loadCachedData();
        startPulse();
    }

    function onHide() {
        stopPulse();
    }

    function onExitSleep() {
        startPulse();
    }

    function onEnterSleep() {
        stopPulse();
    }

    function startPulse() {
        _pulseTimer.start(method(:onPulseTick), PULSE_TICK_MS, true);
    }

    function stopPulse() {
        _pulseTimer.stop();
    }

    function onPulseTick() {
        _pulsePhase += PULSE_STEP;
        if (_pulsePhase > 2 * Math.PI) {
            _pulsePhase -= 2 * Math.PI;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        loadCachedData();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawRings(dc, cx, cy);
        drawMomentaryLine(dc, cx, cy);
        drawTime(dc, cx, cy);
        drawValuesLine(dc, cx, cy);
    }

    // Reads whatever HomePowerFaceApp.onBackgroundData last cached -
    // called every onUpdate (which the system drives, not us) rather
    // than only on data arrival, so a freshly-installed face with no
    // cached data yet still renders (zeros) instead of erroring.
    function loadCachedData() {
        var data = Application.Storage.getValue("lastData");
        if (data == null || !(data instanceof Lang.Dictionary)) { return; }
        _homeToday = getFloat(data, "homeToday", _homeToday);
        _pvDirectToday = getFloat(data, "solarDirectToday", _pvDirectToday);
        _batteryOutToday = getFloat(data, "batteryDischargedToday", _batteryOutToday);
        _gridToday = getFloat(data, "importedToday", _gridToday);
        _liveHome = getFloat(data, "home", _liveHome);
        _liveSolar = getFloat(data, "solar", _liveSolar);
        _liveGrid = getFloat(data, "grid", _liveGrid);
        _liveBatteryPower = getFloat(data, "batteryPower", _liveBatteryPower);
    }

    function getFloat(data, key, fallback) {
        if (!data.hasKey(key) || data[key] == null) { return fallback; }
        return data[key].toFloat();
    }

    // Outer ring: an arc covering only the portion of the day that has
    // elapsed since midnight (2026, user request: "the white circle
    // should be full for 24h so it should cover only how many hours
    // passed from 00:00") - not a full circle. Inner ring: the SAME
    // elapsed-day arc span, divided among Grid/PV-direct/Battery-out by
    // their share of today's total (2026, user request: "the parallel
    // inner circle should follow the white one with the division on the
    // power sources") - whichever source is live right now pulses,
    // the other two sit dimmed. The outer ring pulses too, whenever the
    // house is actively drawing any power at all (2026, user request:
    // "pulsate when something is currently used by the house") - same
    // dim/bright lerp mechanism, just gated on homeActive instead of
    // one of the three source-specific flags.
    function drawRings(dc, cx, cy) {
        var outerR = 205;
        var innerR = 183;
        var penW = 12;

        var clock = System.getClockTime();
        var dayFrac = (clock.hour + (clock.min / 60.0)) / 24.0;
        var dayDeg = dayFrac * 360.0;

        var homeActive = _liveHome > 0.05;
        var t = (Math.sin(_pulsePhase) + 1) / 2;

        dc.setPenWidth(penW);
        dc.setColor(homeActive ? lerpColor(HOME_DIM, HOME_COLOR, t) : HOME_DIM, Graphics.COLOR_BLACK);
        drawRingSegment(dc, cx, cy, outerR, dayDeg, 0.0);

        var total = _gridToday + _pvDirectToday + _batteryOutToday;
        if (total > 0) {
            var gridDeg = (_gridToday / total) * dayDeg;
            var pvDeg = (_pvDirectToday / total) * dayDeg;
            var battDeg = (_batteryOutToday / total) * dayDeg;

            var gridActive = _liveGrid > 0.05;
            var pvActive = _liveSolar > 0.05;
            var battActive = _liveBatteryPower < -0.05;

            var cw = 0.0;
            dc.setColor(gridActive ? lerpColor(GRID_DIM, BRAND_ORANGE, t) : GRID_DIM, Graphics.COLOR_BLACK);
            cw = drawRingSegment(dc, cx, cy, innerR, gridDeg, cw);
            dc.setColor(pvActive ? lerpColor(SOLAR_DIM, SOLAR_COLOR, t) : SOLAR_DIM, Graphics.COLOR_BLACK);
            cw = drawRingSegment(dc, cx, cy, innerR, pvDeg, cw);
            dc.setColor(battActive ? lerpColor(BATTERY_DIM, BATTERY_VIOLET, t) : BATTERY_DIM, Graphics.COLOR_BLACK);
            cw = drawRingSegment(dc, cx, cy, innerR, battDeg, cw);
        }
        dc.setPenWidth(1);
    }

    // Draws one arc `sweepDeg` degrees long, starting `cwStart` degrees
    // clockwise from 12 o'clock, and returns the new cumulative
    // clockwise offset so the next segment can continue from where this
    // one ended. drawArc's angles are standard math angles (degrees
    // counterclockwise from the 3 o'clock position) - converted here
    // from "clockwise-from-12" terms, the natural way to lay consecutive
    // segments around a clock face. Uses whatever color is already set
    // on `dc` - callers set that beforehand so each segment can pulse
    // independently.
    function drawRingSegment(dc, cx, cy, r, sweepDeg, cwStart) {
        if (sweepDeg <= 0) { return cwStart; }
        var cwEnd = cwStart + sweepDeg;
        var mathStart = 90 - cwStart;
        var mathEnd = 90 - cwEnd;
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, mathStart, mathEnd);
        return cwEnd;
    }

    function lerpColor(fromColor, toColor, t) {
        var r1 = (fromColor >> 16) & 0xFF;
        var g1 = (fromColor >> 8) & 0xFF;
        var b1 = fromColor & 0xFF;
        var r2 = (toColor >> 16) & 0xFF;
        var g2 = (toColor >> 8) & 0xFF;
        var b2 = toColor & 0xFF;
        var r = (r1 + ((r2 - r1) * t)).toNumber();
        var g = (g1 + ((g2 - g1) * t)).toNumber();
        var b = (b1 + ((b2 - b1) * t)).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    function drawTime(dc, cx, cy) {
        var clock = System.getClockTime();
        var timeText = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy - 70, Graphics.FONT_NUMBER_MEDIUM, timeText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Momentary (instantaneous, not today's totals) Grid/PV-direct/
    // Battery-out readouts directly above the clock (2026, user request:
    // "directly on top"), each with a small triangle that pulses when
    // that source is actually active right now - same dim/pulse
    // mechanism and active-detection as the inner ring's segments. House
    // (2026, user report: "is missing the HOUSE consume") has no
    // directional triangle - consumption is a sink, not a flow with two
    // ends here - just a plain pulsing number. PV has no real
    // "direction" either (a panel only ever produces), so its triangle
    // always points inward, toward the clock, same as Grid importing;
    // Battery-out's always points outward, matching its "out" name -
    // only Grid's actually flips with real direction. "PV direct" here
    // is just the live total `solar` figure (same approximation
    // drawRings' pvActive already makes) - the API has no live
    // PV-to-home-only split, only today's cumulative one. Smaller font
    // than the totals row below - four groups (one with no triangle,
    // three with) need to fit the same width budget three used to.
    function drawMomentaryLine(dc, cx, cy) {
        var font = Graphics.FONT_XTINY;
        var triLen = 7;
        var triHalfH = 4;
        var innerGap = 5;
        var groupGap = 14;

        var homeActive = _liveHome > 0.05;
        var gridActive = _liveGrid.abs() > 0.05;
        var pvActive = _liveSolar > 0.05;
        var battActive = _liveBatteryPower < -0.05;
        var t = (Math.sin(_pulsePhase) + 1) / 2;

        var homeColor = homeActive ? lerpColor(HOME_DIM, HOME_COLOR, t) : HOME_DIM;
        var pvColor = pvActive ? lerpColor(SOLAR_DIM, SOLAR_COLOR, t) : SOLAR_DIM;
        var gridColor = gridActive ? lerpColor(GRID_DIM, BRAND_ORANGE, t) : GRID_DIM;
        var battColor = battActive ? lerpColor(BATTERY_DIM, BATTERY_VIOLET, t) : BATTERY_DIM;

        var homeText = _liveHome.format("%.2f");
        var pvText = _liveSolar.format("%.2f");
        var gridExporting = _liveGrid < 0;
        var gridText = _liveGrid.abs().format("%.2f");
        var battMag = (_liveBatteryPower < 0) ? -_liveBatteryPower : 0.0;
        var battText = battMag.format("%.2f");

        // Same HOUSE/PV-direct/Grid/Battery-out order as the totals row
        // below, so the two rows read as matching columns.
        var homeW = dc.getTextWidthInPixels(homeText, font);
        var pvW = momentaryGroupWidth(dc, font, triLen, innerGap, pvText);
        var gridW = momentaryGroupWidth(dc, font, triLen, innerGap, gridText);
        var battW = momentaryGroupWidth(dc, font, triLen, innerGap, battText);
        var totalW = homeW + pvW + gridW + battW + (groupGap * 3);

        var y = cy - 110;
        var x = cx - (totalW / 2);

        dc.setColor(homeColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, homeText, Graphics.TEXT_JUSTIFY_LEFT);
        x += homeW + groupGap;
        x = drawMomentaryGroup(dc, x, y, font, pvColor, false, pvText, triLen, triHalfH, innerGap);
        x += groupGap;
        x = drawMomentaryGroup(dc, x, y, font, gridColor, gridExporting, gridText, triLen, triHalfH, innerGap);
        x += groupGap;
        x = drawMomentaryGroup(dc, x, y, font, battColor, true, battText, triLen, triHalfH, innerGap);
    }

    function momentaryGroupWidth(dc, font, triLen, innerGap, text) {
        return triLen + innerGap + dc.getTextWidthInPixels(text, font);
    }

    // Draws [triangle][gap][number] starting at x, returns x after the
    // number so the caller can chain the next group. `pointLeft` faces
    // the triangle's apex left/outward (Grid exporting, Battery-out) or
    // right/inward (Grid importing, PV always).
    function drawMomentaryGroup(dc, x, y, font, color, pointLeft, text, triLen, triHalfH, innerGap) {
        var cyTri = y + (dc.getFontHeight(font) / 2);
        var cxTri = x + (triLen / 2);
        dc.setColor(color, Graphics.COLOR_BLACK);
        var points;
        if (pointLeft) {
            points = [
                [cxTri - (triLen / 2), cyTri],
                [cxTri + (triLen / 2), cyTri - triHalfH],
                [cxTri + (triLen / 2), cyTri + triHalfH],
            ];
        } else {
            points = [
                [cxTri + (triLen / 2), cyTri],
                [cxTri - (triLen / 2), cyTri - triHalfH],
                [cxTri - (triLen / 2), cyTri + triHalfH],
            ];
        }
        dc.fillPolygon(points);

        var numX = x + triLen + innerGap;
        dc.drawText(numX, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        return numX + dc.getTextWidthInPixels(text, font);
    }

    // Just the four numbers, color-coded, nothing else (2026, user
    // request: "just put the values on one line colored in the color
    // code. nothing else") - no labels, no units. Sized down a step
    // (2026, user request: "make the number a bit smaller not to
    // overlap the circles") since the row's width at this height was
    // crowding the inner ring's curve. Measured and drawn as separate
    // left-justified segments (same multi-color-on-one-line trick the
    // companion app's header wordmark uses) so the whole row lands
    // centered as a group.
    function drawValuesLine(dc, cx, cy) {
        var font = Graphics.FONT_SMALL;
        var gap = 16;
        var values = [
            [_homeToday, HOME_COLOR],
            [_pvDirectToday, SOLAR_COLOR],
            [_gridToday, BRAND_ORANGE],
            [_batteryOutToday, BATTERY_VIOLET],
        ];

        var texts = new [values.size()];
        var totalW = 0;
        for (var i = 0; i < values.size(); i += 1) {
            texts[i] = values[i][0].format("%.1f");
            totalW += dc.getTextWidthInPixels(texts[i], font);
            if (i > 0) { totalW += gap; }
        }

        var x = cx - (totalW / 2);
        var y = cy + 39;
        for (var j = 0; j < values.size(); j += 1) {
            dc.setColor(values[j][1], Graphics.COLOR_BLACK);
            dc.drawText(x, y, font, texts[j], Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(texts[j], font) + gap;
        }
    }
}
