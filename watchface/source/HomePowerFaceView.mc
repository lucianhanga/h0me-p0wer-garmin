using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.System;
using Toybox.Application;
using Toybox.Lang;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Math;
using Toybox.ActivityMonitor;
using Toybox.Timer;

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

    // Solar graph's stacked-area split - same composition/colors as the
    // companion watch app's Solar page (PV-to-battery under PV-to-home,
    // total production traced on top).
    const PV_BATTERY_BAND = 0x3DA568;
    const PV_HOME_BAND = 0x8EE3A8;

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

    // Today's hourly solar samples, midnight to now - same fields the
    // companion watch app's Solar page graph uses, same backend
    // contract, no changes needed there.
    var _solarHistory = [];
    var _solarBatteryHistory = [];

    // When the background fetch last actually landed (HomePowerFaceApp.
    // onBackgroundData stamps this), not "now" - a tiny footer, same
    // idea as the companion app's "updated HH:MM" status line.
    var _updatedText = "--:--";

    // Redraws just often enough for the live indicator's travel to read
    // as smooth motion instead of visible jumps (2026, user request:
    // "make the running pixel a bit smoother") - its position is
    // already a continuous function of System.getTimer(), the issue was
    // only ever how often onUpdate actually got called to repaint it.
    // Only ticks while actively being looked at, same reasoning as the
    // pulse timer removed earlier - this is a different, newly-
    // requested purpose (motion, not color breathing), not that coming
    // back.
    var _animTimer;
    const ANIM_TICK_MS = 150;

    function initialize() {
        WatchFace.initialize();
        _animTimer = new Timer.Timer();
    }

    function onLayout(dc) {
    }

    function onShow() {
        loadCachedData();
        startAnim();
    }

    function onHide() {
        stopAnim();
    }

    function onExitSleep() {
        startAnim();
    }

    function onEnterSleep() {
        stopAnim();
    }

    function startAnim() {
        _animTimer.start(method(:onAnimTick), ANIM_TICK_MS, true);
    }

    function stopAnim() {
        _animTimer.stop();
    }

    function onAnimTick() {
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
        // The momentary row (+ its live indicator) and the solar graph
        // above it stay at the OLD anchor - the "5 pixels lower" ask
        // was specifically for "the block of text starting with the
        // time... not from live values above the time" (2026, user
        // correction - an earlier pass wrongly moved this row too,
        // since it shared textCy with the time block below).
        var liveCy = cy + 20;
        drawSolarGraph(dc, cx, liveCy - 92, 68);
        // The time-through-steps block shifted down separately (2026,
        // user requests: +20 earlier, this block's own +5 on top of
        // that), independent of liveCy above.
        var textCy = cy + 35;
        // Time drawn BEFORE the momentary row now, not after (2026, user
        // report: "they are behind") - draws happen back-to-front, so
        // whichever is painted later wins wherever the two sit close
        // enough to overlap.
        drawTime(dc, cx, textCy);
        drawDate(dc, cx, textCy);
        drawMomentaryLine(dc, cx, liveCy);
        // A small traveling dot with a fading tail, bouncing left-right
        // right under the momentary row, to mark it as the live one
        // (2026, user request: "emphasise that the row above the time
        // is the live value... a pixel which travels from left to
        // right and right to left leaving a tail"). Driven by
        // System.getTimer() (ms since boot), not a dedicated Timer -
        // its position is a pure function of elapsed real time, so
        // whatever cadence the system already calls onUpdate at while
        // active is all the animation needs; no new continuously
        // running Timer (2026, user request earlier: "stop the
        // pulsating for all" - this doesn't bring that back).
        drawLiveIndicator(dc, cx, liveCy - 44, 100);
        drawValuesLine(dc, cx, textCy);
        drawSteps(dc, cx, textCy + 86);
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

        if (data.hasKey("solarHistory") && data["solarHistory"] != null) {
            _solarHistory = data["solarHistory"];
        }
        if (data.hasKey("solarBatteryHistory") && data["solarBatteryHistory"] != null) {
            _solarBatteryHistory = data["solarBatteryHistory"];
        }

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
        var penW = 9;

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

    // Stacked-area day graph in the space between the rings' inner top
    // curve and the momentary row, previously empty (2026, user
    // request) - same composition as the companion watch app's Solar
    // page (PV-to-battery under PV-to-home, total production line on
    // top), midnight-to-now on the x-axis. `chartW` is fixed rather
    // than derived from the circle's chord width at this height on
    // purpose: the chord narrows fast this close to the ring, so the
    // WIDTH that matters is the narrowest point across the chart's full
    // height (near its top), not at baselineY - tuned empirically
    // against a screenshot instead of computed, same as the date's
    // position above.
    function drawSolarGraph(dc, cx, baselineY, maxH) {
        var count = _solarHistory.size();
        if (count <= 0) { return; }

        var chartW = 220;
        var left = cx - (chartW / 2);
        var right = cx + (chartW / 2);

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(left, baselineY, right, baselineY);

        // Dynamic Y-axis scale from today's own peak, not a hardcoded
        // ceiling (2026 regression already fixed once in the companion
        // app for the same reason: a quiet day's real peak sits well
        // under any fixed guess, wasting most of the chart's height).
        var peak = maxOf(_solarHistory);
        var maxAbs = peak * 1.1;
        if (maxAbs < 0.5) { maxAbs = 0.5; }

        var clock = System.getClockTime();
        var nowFrac = (clock.hour + (clock.min / 60.0)) / 24.0;
        var nowX = left + (nowFrac * chartW);

        var battCount = _solarBatteryHistory.size();

        var xs = new [count];
        var battYs = new [count];
        var totalYs = new [count];
        for (var i = 0; i < count; i += 1) {
            xs[i] = (count > 1) ? (left + ((i.toFloat() / (count - 1)) * (nowX - left))) : nowX;
            var totalVal = _solarHistory[i];
            var battVal = 0.0;
            if (battCount > 0) {
                // Nearest-neighbor resample onto totalValues' own index
                // range - battValues can be a different (shorter/demo
                // fallback) length, same fix already proven in the
                // companion app's Solar graph.
                var battIdx = (count > 1 && battCount > 1)
                    ? Math.round((i.toFloat() / (count - 1)) * (battCount - 1)).toNumber()
                    : 0;
                battVal = _solarBatteryHistory[battIdx];
            }
            if (battVal.toFloat().abs() > totalVal.toFloat().abs()) { battVal = totalVal; }
            battYs[i] = solarGraphY(battVal, maxAbs, baselineY, maxH);
            totalYs[i] = solarGraphY(totalVal, maxAbs, baselineY, maxH);
        }

        if (count > 1) {
            for (var i = 1; i < count; i += 1) {
                dc.setColor(PV_BATTERY_BAND, Graphics.COLOR_BLACK);
                dc.fillPolygon([
                    [xs[i - 1], baselineY], [xs[i], baselineY],
                    [xs[i], battYs[i]], [xs[i - 1], battYs[i - 1]],
                ]);
                dc.setColor(PV_HOME_BAND, Graphics.COLOR_BLACK);
                dc.fillPolygon([
                    [xs[i - 1], battYs[i - 1]], [xs[i], battYs[i]],
                    [xs[i], totalYs[i]], [xs[i - 1], totalYs[i - 1]],
                ]);
            }

            dc.setColor(SOLAR_COLOR, Graphics.COLOR_BLACK);
            dc.setPenWidth(2);
            for (var j = 1; j < count; j += 1) {
                dc.drawLine(xs[j - 1], totalYs[j - 1], xs[j], totalYs[j]);
            }
            dc.setPenWidth(1);
        }

        // Plain dot, not pulsing - no animation anywhere on this face
        // anymore (2026, user request: "stop the pulsating for all").
        dc.setColor(SOLAR_COLOR, Graphics.COLOR_BLACK);
        dc.fillCircle(xs[count - 1], totalYs[count - 1], 3);
    }

    function solarGraphY(value, maxAbs, baselineY, maxH) {
        var h = ((value.toFloat().abs() / maxAbs) * maxH).toNumber();
        if (h < 0) { h = 0; }
        if (h > maxH) { h = maxH; }
        return baselineY - h;
    }

    // Highest value in a history array, 0.0 for an empty one.
    function maxOf(values) {
        var m = 0.0;
        for (var i = 0; i < values.size(); i += 1) {
            var v = values[i].toFloat();
            if (v > m) { m = v; }
        }
        return m;
    }

    // Seconds appended as a smaller, dimmer, bitmap-scaled suffix (2026,
    // user request: "add seconds to the time") - scaled rather than a
    // second named font so its size is exactly known relative to the
    // big digits, vertically centered against the measured font height
    // (reliable for THIS centering math, even though that same measured
    // height turned out not to reliably predict the digits' visual
    // bottom edge for placing the date below - see drawDate's comment).
    function drawTime(dc, cx, cy) {
        var clock = System.getClockTime();
        var timeText = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        var secText = ":" + clock.sec.format("%02d");

        // FONT_NUMBER_MILD, not MEDIUM - a bit smaller (2026, user
        // request: "make the watch main time font a bit smaller").
        var timeFont = Graphics.FONT_NUMBER_MILD;
        var timeW = dc.getTextWidthInPixels(timeText, timeFont);
        var timeH = dc.getFontHeight(timeFont);
        var y = cy - 70;

        var secScale = 0.65;
        var secTw = dc.getTextWidthInPixels(secText, Graphics.FONT_TINY);
        var secTh = dc.getFontHeight(Graphics.FONT_TINY);
        var secDestW = (secTw * secScale).toNumber();
        var secDestH = (secTh * secScale).toNumber();
        var gap = 4;

        var startX = cx - ((timeW + gap + secDestW) / 2);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(startX, y, timeFont, timeText, Graphics.TEXT_JUSTIFY_LEFT);

        var secY = y + ((timeH - secDestH) / 2);
        drawScaledText(dc, startX + timeW + gap, secY, secText, Graphics.FONT_TINY,
            Graphics.COLOR_LT_GRAY, secScale, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Small date line directly under the time (2026, user request: "I
    // also want the date"), now with the year too (2026, user request:
    // "add also the year") - "Oct 5 2026" via Gregorian.FORMAT_MEDIUM's
    // abbreviated month name. A fixed offset from cy, not from
    // drawTime's measured font height - that measured height turned out
    // to include much more padding than the digits' actual visual
    // bottom (twice: first with FONT_NUMBER_MEDIUM, then again after
    // switching to MILD), landing the date on top of the totals row
    // both times. Tuned empirically against a screenshot instead.
    function drawDate(dc, cx, cy) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateText = info.month + " " + info.day + " " + info.year;
        drawScaledText(dc, cx, cy + 16, dateText, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, 0.65,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Momentary (instantaneous, not today's totals) House/PV-direct/
    // Grid/Battery readouts directly above the clock, each at full color
    // when actually active right now, dimmed otherwise (no animation -
    // see the DIM constants' comment) - same active-detection as the
    // inner ring's segments, and now the SAME icon glyphs the totals
    // row uses too (2026, user request: "put the symbols also to the
    // row with the momentary values"). Only Battery keeps its
    // directional triangle ALONGSIDE its icon (2026, user request:
    // "observe that the triangle... is not touched!") - it's the one
    // source here with a real two-way flow (charging in, discharging
    // out); House/PV/Grid are icon+number only. "PV direct" here is
    // just the live total `solar` figure (same approximation drawRings'
    // pvActive already makes) - the API has no live PV-to-home-only
    // split, only today's cumulative one.
    function drawMomentaryLine(dc, cx, cy) {
        var font = Graphics.FONT_XTINY;
        var iconSize = 11;
        var iconGap = 4;
        var triLen = 6;
        var triHalfH = 3;
        var groupGap = 12;

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
        // below, so the two rows read as matching columns. Battery's
        // direction triangle sits UNDER its icon now, not inline before
        // the number (2026, user request: "put the direction triangle
        // of the battery under the battery symbol so you reduce the
        // line lengths" - also fixes the row overlapping the rings a
        // bit, since it's shorter now), so its group width is just
        // icon+number like the other three, no separate triangle lane.
        var homeW = iconSize + iconGap + dc.getTextWidthInPixels(homeText, font);
        var pvW = iconSize + iconGap + dc.getTextWidthInPixels(pvText, font);
        var gridW = iconSize + iconGap + dc.getTextWidthInPixels(gridText, font);
        var battW = iconSize + iconGap + dc.getTextWidthInPixels(battText, font);
        var totalW = homeW + pvW + gridW + battW + (groupGap * 3);

        var y = cy - 85;
        var x = cx - (totalW / 2);
        var yCenter = y + (dc.getFontHeight(font) / 2);

        drawHouseIcon(dc, x + (iconSize / 2), yCenter, iconSize, homeColor);
        x += iconSize + iconGap;
        dc.setColor(homeColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, homeText, Graphics.TEXT_JUSTIFY_LEFT);
        x += dc.getTextWidthInPixels(homeText, font) + groupGap;

        drawSunIcon(dc, x + (iconSize / 2), yCenter, iconSize, pvColor);
        x += iconSize + iconGap;
        dc.setColor(pvColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, pvText, Graphics.TEXT_JUSTIFY_LEFT);
        x += dc.getTextWidthInPixels(pvText, font) + groupGap;

        drawBoltIcon(dc, x + (iconSize / 2), yCenter, iconSize, gridColor);
        x += iconSize + iconGap;
        dc.setColor(gridColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, gridText, Graphics.TEXT_JUSTIFY_LEFT);
        x += dc.getTextWidthInPixels(gridText, font) + groupGap;

        // Discharging (flowing out) points left/outward, charging
        // (flowing in) points right/inward - same convention the
        // companion watch app's Overview/Battery pages use.
        drawBatteryIconWithDirection(dc, x + (iconSize / 2), yCenter, iconSize, battColor,
            battDischarging, triLen, triHalfH);
        x += iconSize + iconGap;
        dc.setColor(battColor, Graphics.COLOR_BLACK);
        dc.drawText(x, y, font, battText, Graphics.TEXT_JUSTIFY_LEFT);
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
        var y = cy + 41;
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

    // Same battery icon, plus a small direction triangle stacked
    // directly underneath it (2026, user request: "put the direction
    // triangle of the battery under the battery symbol so you reduce
    // the line lengths") - used only by the momentary row, which is the
    // one place direction matters; the totals row's battery icon has no
    // direction to show, so it stays the plain drawBatteryIcon above.
    function drawBatteryIconWithDirection(dc, x, yCenter, size, color, pointLeft, triLen, triHalfH) {
        drawBatteryIcon(dc, x, yCenter, size, color);

        var half = size / 2.0;
        var triY = yCenter + half + 3 + triHalfH;
        dc.setColor(color, Graphics.COLOR_BLACK);
        var points;
        if (pointLeft) {
            points = [
                [x - (triLen / 2), triY],
                [x + (triLen / 2), triY - triHalfH],
                [x + (triLen / 2), triY + triHalfH],
            ];
        } else {
            points = [
                [x + (triLen / 2), triY],
                [x - (triLen / 2), triY - triHalfH],
                [x - (triLen / 2), triY + triHalfH],
            ];
        }
        dc.fillPolygon(points);
    }

    // Renders text at `font`'s native size into an offscreen buffer,
    // then blits it scaled down by `scale` - genuinely smaller than any
    // text font this device exposes, same bitmap-scaling technique the
    // companion watch app's drawScaledText uses (2026, user request:
    // "a very small timestamp").
    function drawScaledText(dc, x, y, text, font, color, scale, justify) {
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
        var destX;
        if (justify == Graphics.TEXT_JUSTIFY_RIGHT) {
            destX = x - destW;
        } else if (justify == Graphics.TEXT_JUSTIFY_CENTER) {
            destX = x - (destW / 2);
        } else {
            destX = x;
        }
        dc.drawScaledBitmap(destX, y, destW, destH, bmp);
    }

    // Bounces a small dot back and forth across a `2*halfWidth`-wide
    // span centered on `cx`, with a short fading tail behind it in
    // whichever direction it's currently traveling - discrete stepped
    // squares, not a true alpha blend (matches the blocky look of the
    // reference images, and dc has no per-pixel alpha for fills anyway).
    function drawLiveIndicator(dc, cx, y, halfWidth) {
        var travelMs = 4000;
        var tailLen = 6;
        var step = 6;
        var dotSize = 4;

        var t = System.getTimer() % travelMs;
        var frac = t.toFloat() / travelMs;
        var pos;
        var movingRight;
        if (frac < 0.5) {
            pos = frac * 2;
            movingRight = true;
        } else {
            pos = 2.0 - (frac * 2);
            movingRight = false;
        }
        var headX = (cx - halfWidth) + (pos * 2 * halfWidth);
        var half = dotSize / 2.0;

        for (var i = tailLen - 1; i >= 0; i -= 1) {
            var tailX = movingRight ? headX - (i * step) : headX + (i * step);
            var gray = 255 - ((255 * i) / tailLen).toNumber();
            var color = (gray << 16) | (gray << 8) | gray;
            dc.setColor(color, Graphics.COLOR_BLACK);
            dc.fillRectangle((tailX - half).toNumber(), (y - half).toNumber(), dotSize, dotSize);
        }
    }

    // Today's step count, directly under the totals row (2026, user
    // request: "under the last text row add the number of steps made
    // today") - Toybox.ActivityMonitor, not the backend; this has
    // nothing to do with h0me-p0wer's own data.
    function drawSteps(dc, cx, y) {
        var info = ActivityMonitor.getInfo();
        var steps = (info != null && info.steps != null) ? info.steps : 0;
        drawScaledText(dc, cx, y, steps.format("%d") + " steps", Graphics.FONT_XTINY,
            Graphics.COLOR_LT_GRAY, 0.6, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // As low as the round bezel safely allows (2026, user request: "as
    // low as possible") - `h` is the full screen height, not cy, so this
    // doesn't need to know the center to sit near the very bottom edge.
    function drawUpdatedText(dc, cx, h) {
        drawScaledText(dc, cx, h - 70, "updated " + _updatedText, Graphics.FONT_XTINY,
            Graphics.COLOR_LT_GRAY, 0.42, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
