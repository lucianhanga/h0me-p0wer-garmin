using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Application;
using Toybox.Lang;

class HomePowerFaceView extends WatchUi.WatchFace {
    // Same brand palette as the companion watch app
    // (h0me-p0wer-garmin/source/HomePowerView.mc) - solar green, grid
    // orange, battery violet, home neutral off-white.
    const SOLAR_COLOR = 0x5FCE80;
    const BRAND_ORANGE = 0xF7A44F;
    const BATTERY_VIOLET = 0xC084FC;
    const HOME_COLOR = 0xE8ECEF;

    // Dimmed shades each inner-ring segment (and momentary readout) sits
    // at while its source isn't currently active - full color otherwise.
    // Used to be an animated pulse between these two (Timer-driven), but
    // that's gone now (2026, user request: "stop the pulsating for
    // all") - just a static two-state color, no animation, no Timer.
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
    // tell which source is actively flowing right now.
    var _liveHome = 0.0;
    var _liveSolar = 0.0;
    var _liveGrid = 0.0;
    var _liveBatteryPower = 0.0;

    // When the background fetch last actually landed (HomePowerFaceApp.
    // onBackgroundData stamps this), not "now" - a tiny footer, same
    // idea as the companion app's "updated HH:MM" status line.
    var _updatedText = "--:--";

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
    }

    function onShow() {
        loadCachedData();
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
        // Time drawn BEFORE the momentary row now, not after (2026, user
        // report: "they are behind") - draws happen back-to-front, so
        // whichever is painted later wins wherever the two sit close
        // enough to overlap.
        drawTime(dc, cx, cy);
        drawMomentaryLine(dc, cx, cy);
        drawValuesLine(dc, cx, cy);
        drawUpdatedText(dc, cx, h);
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

        var updated = Application.Storage.getValue("lastUpdateText");
        if (updated != null && updated instanceof Lang.String) {
            _updatedText = updated;
        }
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
    // power sources") - whichever source is live right now shows at full
    // color, the other two sit dimmed (no animation - see the DIM
    // constants' comment). The outer ring follows the same rule, gated
    // on the house actively drawing any power at all.
    function drawRings(dc, cx, cy) {
        var outerR = 205;
        var innerR = 183;
        var penW = 12;

        var clock = System.getClockTime();
        var dayFrac = (clock.hour + (clock.min / 60.0)) / 24.0;
        var dayDeg = dayFrac * 360.0;

        var homeActive = _liveHome > 0.05;

        dc.setPenWidth(penW);
        dc.setColor(homeActive ? HOME_COLOR : HOME_DIM, Graphics.COLOR_BLACK);
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
            dc.setColor(gridActive ? BRAND_ORANGE : GRID_DIM, Graphics.COLOR_BLACK);
            cw = drawRingSegment(dc, cx, cy, innerR, gridDeg, cw);
            dc.setColor(pvActive ? SOLAR_COLOR : SOLAR_DIM, Graphics.COLOR_BLACK);
            cw = drawRingSegment(dc, cx, cy, innerR, pvDeg, cw);
            dc.setColor(battActive ? BATTERY_VIOLET : BATTERY_DIM, Graphics.COLOR_BLACK);
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

    function drawTime(dc, cx, cy) {
        var clock = System.getClockTime();
        var timeText = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, cy - 70, Graphics.FONT_NUMBER_MEDIUM, timeText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Momentary (instantaneous, not today's totals) House/PV-direct/
    // Grid/Battery readouts directly above the clock, each at full color
    // when actually active right now, dimmed otherwise (no animation -
    // see the DIM constants' comment) - same active-detection as the
    // inner ring's segments. Only Battery gets a directional triangle
    // (2026, user request: "the triangles for in and out should be used
    // for battery only") - it's the one source here with a real two-way
    // flow (charging in, discharging out); House/PV/Grid are plain
    // numbers. "PV direct" here is just the live total `solar` figure
    // (same approximation drawRings' pvActive already makes) - the API
    // has no live PV-to-home-only split, only today's cumulative one.
    function drawMomentaryLine(dc, cx, cy) {
        var font = Graphics.FONT_XTINY;
        var triLen = 7;
        var triHalfH = 4;
        var innerGap = 5;
        var groupGap = 14;

        var homeActive = _liveHome > 0.05;
        var pvActive = _liveSolar > 0.05;
        var gridActive = _liveGrid.abs() > 0.05;
        var battActive = _liveBatteryPower.abs() > 0.05;

        var homeColor = homeActive ? HOME_COLOR : HOME_DIM;
        var pvColor = pvActive ? SOLAR_COLOR : SOLAR_DIM;
        var gridColor = gridActive ? BRAND_ORANGE : GRID_DIM;
        var battColor = battActive ? BATTERY_VIOLET : BATTERY_DIM;

        var homeText = _liveHome.format("%.2f");
        var pvText = _liveSolar.format("%.2f");
        var gridText = _liveGrid.abs().format("%.2f");
        var battDischarging = _liveBatteryPower < 0;
        var battText = _liveBatteryPower.abs().format("%.2f");

        // Same HOUSE/PV-direct/Grid/Battery order as the totals row
        // below, so the two rows read as matching columns.
        var homeW = dc.getTextWidthInPixels(homeText, font);
        var pvW = dc.getTextWidthInPixels(pvText, font);
        var gridW = dc.getTextWidthInPixels(gridText, font);
        var battW = momentaryGroupWidth(dc, font, triLen, innerGap, battText);
        var totalW = homeW + pvW + gridW + battW + (groupGap * 3);

        var y = cy - 85;
        var x = cx - (totalW / 2);

        dc.setColor(homeColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, homeText, Graphics.TEXT_JUSTIFY_LEFT);
        x += homeW + groupGap;
        dc.setColor(pvColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, pvText, Graphics.TEXT_JUSTIFY_LEFT);
        x += pvW + groupGap;
        dc.setColor(gridColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, gridText, Graphics.TEXT_JUSTIFY_LEFT);
        x += gridW + groupGap;
        // Battery's triangle flips with real direction: discharging
        // (flowing out) points left/outward, charging (flowing in)
        // points right/inward - same convention the companion watch
        // app's Overview/Battery pages use.
        x = drawMomentaryGroup(dc, x, y, font, battColor, battDischarging, battText, triLen, triHalfH, innerGap);
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

    // The four today's-totals numbers, color-coded, each preceded by a
    // small hand-drawn glyph identifying it by SHAPE too, not just color
    // (2026, user request: "add logos which represent each value") -
    // Monkey C has no icon font to lean on, so these are plain vector
    // primitives. Sized down a step again (2026, user request: "make
    // the numbers a bit smaller") to make room for them without
    // crowding the inner ring's curve. Measured and drawn as separate
    // left-justified segments (same multi-color-on-one-line trick the
    // companion app's header wordmark uses) so the whole row lands
    // centered as a group.
    function drawValuesLine(dc, cx, cy) {
        var font = Graphics.FONT_XTINY;
        var gap = 14;
        var iconSize = 12;
        var iconGap = 4;

        var texts = [
            _homeToday.format("%.1f"),
            _pvDirectToday.format("%.1f"),
            _gridToday.format("%.1f"),
            _batteryOutToday.format("%.1f"),
        ];
        var colors = [HOME_COLOR, SOLAR_COLOR, BRAND_ORANGE, BATTERY_VIOLET];

        var totalW = 0;
        for (var i = 0; i < texts.size(); i += 1) {
            totalW += iconSize + iconGap + dc.getTextWidthInPixels(texts[i], font);
            if (i > 0) { totalW += gap; }
        }

        var x = cx - (totalW / 2);
        var y = cy + 44;
        var yCenter = y + (dc.getFontHeight(font) / 2);

        drawHouseIcon(dc, x + (iconSize / 2), yCenter, iconSize, colors[0]);
        x += iconSize + iconGap;
        dc.setColor(colors[0], Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, texts[0], Graphics.TEXT_JUSTIFY_LEFT);
        x += dc.getTextWidthInPixels(texts[0], font) + gap;

        drawSunIcon(dc, x + (iconSize / 2), yCenter, iconSize, colors[1]);
        x += iconSize + iconGap;
        dc.setColor(colors[1], Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, texts[1], Graphics.TEXT_JUSTIFY_LEFT);
        x += dc.getTextWidthInPixels(texts[1], font) + gap;

        drawBoltIcon(dc, x + (iconSize / 2), yCenter, iconSize, colors[2]);
        x += iconSize + iconGap;
        dc.setColor(colors[2], Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, texts[2], Graphics.TEXT_JUSTIFY_LEFT);
        x += dc.getTextWidthInPixels(texts[2], font) + gap;

        drawBatteryIcon(dc, x + (iconSize / 2), yCenter, iconSize, colors[3]);
        x += iconSize + iconGap;
        dc.setColor(colors[3], Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, texts[3], Graphics.TEXT_JUSTIFY_LEFT);
    }

    // House: a simple pentagon silhouette (peaked roof + square base) in
    // one fillPolygon call.
    function drawHouseIcon(dc, x, yCenter, size, color) {
        var half = size / 2.0;
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillPolygon([
            [x, yCenter - half],
            [x - half, yCenter - (half * 0.15)],
            [x - half, yCenter + half],
            [x + half, yCenter + half],
            [x + half, yCenter - (half * 0.15)],
        ]);
    }

    // PV direct: a filled circle with four short rays - a plain sun.
    function drawSunIcon(dc, x, yCenter, size, color) {
        var half = size / 2.0;
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillCircle(x, yCenter, half * 0.55);
        dc.drawLine(x, yCenter - half, x, yCenter - (half * 0.65));
        dc.drawLine(x, yCenter + (half * 0.65), x, yCenter + half);
        dc.drawLine(x - half, yCenter, x - (half * 0.65), yCenter);
        dc.drawLine(x + (half * 0.65), yCenter, x + half, yCenter);
    }

    // Grid: a simple lightning-bolt zigzag, one fillPolygon call.
    function drawBoltIcon(dc, x, yCenter, size, color) {
        var half = size / 2.0;
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillPolygon([
            [x - (half * 0.2), yCenter - half],
            [x + (half * 0.5), yCenter - (half * 0.1)],
            [x, yCenter - (half * 0.1)],
            [x + (half * 0.2), yCenter + half],
            [x - (half * 0.5), yCenter + (half * 0.1)],
            [x, yCenter + (half * 0.1)],
        ]);
    }

    // Battery: a rounded-rectangle body with a small terminal nub.
    function drawBatteryIcon(dc, x, yCenter, size, color) {
        var half = size / 2.0;
        var bodyW = size * 0.8;
        var bodyH = size * 0.55;
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle((x - half).toNumber(), (yCenter - (bodyH / 2)).toNumber(),
            bodyW.toNumber(), bodyH.toNumber(), 2);
        var nubW = size * 0.15;
        var nubH = bodyH * 0.5;
        dc.fillRectangle((x - half + bodyW).toNumber(), (yCenter - (nubH / 2)).toNumber(),
            nubW.toNumber(), nubH.toNumber());
    }

    // Renders text at `font`'s native size into an offscreen buffer,
    // then blits it scaled down by `scale` - genuinely smaller than any
    // text font this device exposes, same bitmap-scaling technique the
    // companion watch app's drawScaledText uses (2026, user request:
    // "a very small timestamp"). Center-justified only - the one caller
    // here doesn't need more.
    function drawScaledText(dc, cx, y, text, font, color, scale) {
        var tw = dc.getTextWidthInPixels(text, font);
        var th = dc.getFontHeight(font);
        if (tw <= 0 || th <= 0) { return; }

        var bmpRef = Graphics.createBufferedBitmap({ :width => tw, :height => th });
        var bmp = bmpRef.get();
        var bdc = bmp.getDc();
        bdc.setColor(color, Graphics.COLOR_BLACK);
        bdc.clear();
        bdc.drawText(0, 0, font, text, Graphics.TEXT_JUSTIFY_LEFT);

        var destW = (tw * scale).toNumber();
        var destH = (th * scale).toNumber();
        dc.drawScaledBitmap(cx - (destW / 2), y, destW, destH, bmp);
    }

    // As low as the round bezel safely allows (2026, user request: "as
    // low as possible") - `h` is the full screen height, not cy, so this
    // doesn't need to know the center to sit near the very bottom edge.
    function drawUpdatedText(dc, cx, h) {
        drawScaledText(dc, cx, h - 70, "updated " + _updatedText, Graphics.FONT_XTINY,
            Graphics.COLOR_LT_GRAY, 0.42);
    }
}
