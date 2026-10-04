using Toybox.Graphics;
using Toybox.WatchUi;
using Toybox.Timer;
using Toybox.System;
using Toybox.Math;

class HomePowerView extends WatchUi.View {
    const PAGE_COUNT = 7;

    // Layout tuned specifically for the 454x454 round AMOLED display used by
    // the Fenix 8 47 mm / 51 mm. All large text stays inside the wide middle
    // portion of the circle; only small footer elements sit near the lower
    // edge.
    //
    // Vertical spacing throughout this file is derived from this device's
    // ACTUAL font pixel heights (measured via dc.getFontHeight(), not
    // guessed): FONT_XTINY=37, FONT_TINY=47, FONT_SMALL=53, FONT_MEDIUM=61.
    // drawText's y is the TOP of the text's bounding box, so two stacked
    // lines need their gap to be at least the first line's full font
    // height, not just enough room for the glyphs' visual ink - otherwise
    // the second line's box starts before the first line's box ends and
    // they render on top of each other.
    const SAFE_LEFT = 86;
    const SAFE_RIGHT = 368;
    const HEADER_LINE_Y = 55;
    const FOOTER_STATUS_Y = 372;
    const FOOTER_DOTS_Y = 428;

    var _page = 0;
    var _online = true;
    var _loading = false;
    var _model;
    var _service;

    // Pulsing "now" dot on the Solar day graph - ticks independently of
    // the data-refresh timer (which runs every REFRESH_MS, far too slow
    // for a visible pulse) purely to animate, redrawing the whole screen
    // each tick since Monkey C has no partial-redraw primitive.
    var _pulseTimer;
    var _pulsePhase = 0.0;
    const PULSE_TICK_MS = 250;
    const PULSE_STEP = 0.5; // radians per tick

    function initialize() {
        View.initialize();
        _model = new HomePowerModel();
        _service = new HomePowerService(self, _model);
        _pulseTimer = new Timer.Timer();
    }

    function onShow() {
        _service.start();
        _pulseTimer.start(method(:onPulseTick), PULSE_TICK_MS, true);
    }

    function onHide() {
        _service.stop();
        _pulseTimer.stop();
    }

    function onPulseTick() {
        _pulsePhase += PULSE_STEP;
        if (_pulsePhase > 2 * Math.PI) {
            _pulsePhase -= 2 * Math.PI;
        }
        WatchUi.requestUpdate();
    }

    function isOnline() {
        return _online;
    }

    function setConnectionState(online, loading) {
        _online = online;
        _loading = loading;
    }

    function nextPage() {
        _page = (_page + 1) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function previousPage() {
        _page = (_page + PAGE_COUNT - 1) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function activate() {
        if (_page == 6 || !_online) {
            _service.refresh();
        } else {
            nextPage();
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawHeader(dc);

        if (_page == 0) { drawOverview(dc); }
        else if (_page == 1) { drawSolar(dc); }
        else if (_page == 2) { drawHome(dc); }
        else if (_page == 3) { drawBattery(dc); }
        else if (_page == 4) { drawGrid(dc); }
        else if (_page == 5) { drawList(dc); }
        else { drawConnection(dc); }

        drawFooter(dc);
    }

    // Brand wordmark "h0mep0wer" with orange zeros, matching the web app
    // (web/src/App.jsx .brand / .brand-zero, #F7A44F). A single drawText
    // call can't mix colors, so this measures and draws each segment in
    // turn, left to right, to land the whole thing centered.
    const BRAND_ORANGE = 0xF7A44F;
    const BRAND_SEGMENTS = ["h", "0", "mep", "0", "wer"];

    // Same 4-category color convention as the web app (web/src/styles.css
    // .wx-c-grid/.wx-c-pv/.wx-c-batt, ~line 1795-1797): Grid is always this
    // one orange (not direction-dependent - import and export share it,
    // direction is conveyed by sign/position, not color), Solar/PV is this
    // green, Battery is this violet for discharge specifically, with
    // charging using a separate, deliberately muted grey instead of its
    // own violet shade. Home has no brand color in the web app either -
    // it's the neutral aggregate, rendered in this same off-white used for
    // the web app's house chart series (web/src/live/LiveTab.jsx:221).
    const SOLAR_COLOR = 0x5FCE80;
    const HOME_COLOR = 0xE8ECEF;
    const BATTERY_VIOLET = 0xC084FC;
    const BATTERY_CHARGE_GREY = 0x8B98A5;

    // Solar page's production graph: same stacked-area split the web app's
    // Graph tab uses for "Power Production" (web/src/graph/GraphTab.jsx) -
    // PV-to-battery stacked under PV-to-home, with the total production
    // traced as a plain line on top in the standard PV green above.
    const PV_BATTERY_BAND = 0x3DA568;
    const PV_HOME_BAND = 0x8EE3A8;

    function drawHeader(dc) {
        var w = dc.getWidth();
        var font = Graphics.FONT_XTINY;

        var totalW = 0;
        for (var i = 0; i < BRAND_SEGMENTS.size(); i += 1) {
            totalW += dc.getTextWidthInPixels(BRAND_SEGMENTS[i], font);
        }

        var x = (w / 2) - (totalW / 2);
        for (var j = 0; j < BRAND_SEGMENTS.size(); j += 1) {
            var seg = BRAND_SEGMENTS[j];
            dc.setColor(seg.equals("0") ? BRAND_ORANGE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(x, 14, font, seg, Graphics.TEXT_JUSTIFY_LEFT);
            x += dc.getTextWidthInPixels(seg, font);
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(108, HEADER_LINE_Y, w - 108, HEADER_LINE_Y);
    }

    function drawFooter(dc) {
        var w = dc.getWidth();
        var status = _loading ? "updating..." : (_online ? "updated " + _model.updatedText : "offline - cached");

        dc.setColor(_online ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_RED, Graphics.COLOR_BLACK);
        dc.drawText(w / 2, FOOTER_STATUS_Y, Graphics.FONT_XTINY, status, Graphics.TEXT_JUSTIFY_CENTER);

        // Eight small dots are much safer on a round screen than a wide
        // "1/8  up/down pages" string near the lower bezel.
        var firstX = (w / 2) - 42;
        for (var i = 0; i < PAGE_COUNT; i += 1) {
            dc.setColor(i == _page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
            dc.fillCircle(firstX + (i * 12), FOOTER_DOTS_Y, i == _page ? 4 : 2);
        }
    }

    // The "live view" - momentary power for all four quantities, no dots
    // (the label's own color already carries the category identity), no
    // +/- signs on the numbers (direction is conveyed by the Grid arrow
    // and Battery symbol instead). Each cell is a label line (XTINY) +
    // one "value unit" line (SMALL) - two lines total, same budget as
    // before now that removing the dot freed ~18px per cell.
    function drawOverview(dc) {
        var w = dc.getWidth();
        var cx = w / 2;
        var leftX = 140;
        var rightX = w - 140;
        var row1Y = 77;
        var row2Y = 247;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(cx, 64, cx, 366);
        dc.drawLine(92, 217, w - 92, 217);

        overviewLabel(dc, leftX, row1Y, "SOLAR", SOLAR_COLOR);
        overviewValue(dc, leftX, row1Y, kwNumber(_model.solarKw), "kW");

        overviewLabel(dc, rightX, row1Y, "HOME", HOME_COLOR);
        overviewValue(dc, rightX, row1Y, kwNumber(_model.homeKw), "kW");

        // "<- GRID" (exporting/pushing, triangle before the word) or
        // "GRID ->" (importing/pulling, triangle after) - direction via a
        // drawn, pulsing triangle instead of a +/- sign.
        var exporting = _model.gridKw < 0;
        drawDirectionalLabel(dc, leftX, row2Y, "GRID", exporting, BRAND_ORANGE, 0x4A3018);
        overviewValue(dc, leftX, row2Y, kwNumber(_model.gridKw.abs()), "kW");

        // Charge/discharge rate (2026, user request: "how much you pull
        // from battery too" - the Live tab equivalent on the phone app
        // shows this rate, not just the charge %, which stays available
        // on the Battery page). Same triangle-before/after-word pattern
        // as Grid: discharging (out of the battery) mirrors "exporting" -
        // triangle before the word; charging (into the battery) mirrors
        // "importing" - triangle after. Violet discharging, grey
        // charging/idle, the web app's own battery color convention.
        var charging = _model.batteryKw > 0.02;
        var discharging = _model.batteryKw < -0.02;
        var batteryColor = discharging ? BATTERY_VIOLET : BATTERY_CHARGE_GREY;
        if (charging || discharging) {
            var dim = charging ? 0x2E3134 : 0x3A2550;
            drawDirectionalLabel(dc, rightX, row2Y, "BATTERY", discharging, batteryColor, dim);
        } else {
            overviewLabel(dc, rightX, row2Y, "BATTERY", BATTERY_CHARGE_GREY);
        }
        overviewValue(dc, rightX, row2Y, kwNumber(_model.batteryKw.abs()), "kW");
    }

    function overviewLabel(dc, x, y, label, color) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(x, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // `word` + a drawn triangle, pulsing between `dimColor` and `color` -
    // a filled polygon rather than a text arrow glyph, since font arrow
    // glyph support isn't guaranteed on this device. `triangleBefore`
    // puts a left-pointing triangle before the word (e.g. Grid exporting,
    // Battery discharging - both "flowing out"); false puts a
    // right-pointing triangle after it (Grid importing, Battery charging
    // - both "flowing in"). Shared by the Grid and Battery cells.
    function drawDirectionalLabel(dc, x, y, word, triangleBefore, color, dimColor) {
        var wordW = dc.getTextWidthInPixels(word, Graphics.FONT_XTINY);
        var gap = 8;
        var triLen = 13;
        var triHalfH = 7;
        var totalW = wordW + gap + triLen;
        var startX = x - (totalW / 2);
        var cyTri = y + 18; // vertical middle of the FONT_XTINY text box

        var wordX;
        var cxTri;
        if (triangleBefore) {
            cxTri = startX + (triLen / 2);
            wordX = startX + triLen + gap;
        } else {
            wordX = startX;
            cxTri = startX + wordW + gap + (triLen / 2);
        }

        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(wordX, y, Graphics.FONT_XTINY, word, Graphics.TEXT_JUSTIFY_LEFT);

        var t = (Math.sin(_pulsePhase) + 1) / 2; // 0..1 breathing factor
        dc.setColor(lerpColor(dimColor, color, t), Graphics.COLOR_BLACK);
        var points;
        if (triangleBefore) {
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
    }

    function overviewValue(dc, x, y, number, unit) {
        // Label height (37) + 4px gap - label now starts at the cell's own
        // y (no dot above it eating space), so this replaces the old y+59.
        drawSplitUnit(dc, x, y + 41, number, unit, Graphics.FONT_SMALL, Graphics.FONT_XTINY,
            Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
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

    // Draws "number unit" (e.g. "4.20 kW") with the unit in a smaller font
    // and dimmer color than the number - XTINY (37px) is the smallest text
    // font this device exposes, so "smaller" than that isn't achievable
    // without a custom bitmap font; the dimmer gray is what stands in for
    // further size reduction. Both pieces are measured and drawn as two
    // left-justified segments so the pair as a whole still lands centered
    // or right-aligned per `justify`, the same trick the header wordmark
    // uses for its multi-color text.
    function drawSplitUnit(dc, x, y, number, unit, numberFont, unitFont, numberColor, justify) {
        var numberW = dc.getTextWidthInPixels(number, numberFont);
        var hasUnit = !unit.equals("");
        var unitText = hasUnit ? (" " + unit) : "";
        var unitW = hasUnit ? dc.getTextWidthInPixels(unitText, unitFont) : 0;
        var totalW = numberW + unitW;

        var startX;
        if (justify == Graphics.TEXT_JUSTIFY_RIGHT) {
            startX = x - totalW;
        } else if (justify == Graphics.TEXT_JUSTIFY_CENTER) {
            startX = x - (totalW / 2);
        } else {
            startX = x;
        }

        dc.setColor(numberColor, Graphics.COLOR_BLACK);
        dc.drawText(startX, y, numberFont, number, Graphics.TEXT_JUSTIFY_LEFT);

        if (hasUnit) {
            // Lines up the unit's bottom with the number's bottom (nudged
            // 2px up from an exact bottom-match, which read as slightly low).
            var dy = dc.getFontHeight(numberFont) - dc.getFontHeight(unitFont) - 2;
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(startX + numberW, y + dy, unitFont, unitText, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function drawSolar(dc) {
        title(dc, "SOLAR", SOLAR_COLOR);
        mainMetric(dc, kwNumber(_model.solarKw), "kW");
        drawSolarDayGraph(dc, _model.solarHistory, _model.solarBatteryHistory, 4.8, 256, 60);
        bottomPair(dc, "TODAY", kwhNumber(_model.solarTodayKwh), "kWh", "PEAK", "4.6", "kW");
    }

    function drawHome(dc) {
        title(dc, "HOME", HOME_COLOR);
        mainMetric(dc, kwNumber(_model.homeKw), "kW");
        drawBars(dc, _model.homeHistory, 3.0, 263, 40, HOME_COLOR, false);
        bottomPair(dc, "TODAY", kwhNumber(_model.homeTodayKwh), "kWh", "NOW", kwNumber(_model.homeKw), "kW");
    }

    function drawBattery(dc) {
        var w = dc.getWidth();
        var cx = w / 2;

        title(dc, "BATTERY", BATTERY_VIOLET);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, 120, Graphics.FONT_MEDIUM, _model.batteryPct.format("%d") + "%", Graphics.TEXT_JUSTIFY_CENTER);

        // Horizontal fill bar instead of a circular gauge - the arc-angle
        // direction semantics on this device didn't behave as documented
        // (a "280 degree clockwise from top" sweep rendered as a small
        // sliver instead), so this reuses the same plain rectangle-fill
        // approach already proven by drawBars elsewhere in this file. This
        // shows state of charge, not direction, so it stays the battery's
        // identity violet regardless of charge/discharge.
        // 120 (percent offset) + 61 (FONT_MEDIUM height) + 6px gap.
        var barY = 187;
        var barH = 18;
        var barW = SAFE_RIGHT - SAFE_LEFT;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawRoundedRectangle(SAFE_LEFT, barY, barW, barH, 6);
        var fillW = (barW * _model.batteryPct) / 100;
        dc.setColor(BATTERY_VIOLET, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(SAFE_LEFT, barY, fillW, barH, 6);

        // Rate DOES encode direction, so it switches color same as the
        // Overview cell: violet discharging, grey charging.
        var rateColor = _model.batteryKw < 0 ? BATTERY_VIOLET : BATTERY_CHARGE_GREY;
        // 187 + 18 (bar height) + 12px gap.
        drawSplitUnit(dc, cx, 217, signedKwNumber(_model.batteryKw), "kW", Graphics.FONT_MEDIUM, Graphics.FONT_XTINY,
            rateColor, Graphics.TEXT_JUSTIFY_CENTER);

        // 217 + 61 (FONT_MEDIUM height) + 12px gap.
        bottomPairAt(dc, 290, "TO FULL", minutes(_model.batteryMinutesToFull), "",
            "CAPACITY", kwhNumber(_model.batteryCapacityKwh), "kWh");
    }

    function drawGrid(dc) {
        // Grid is always this one orange in the web app - not direction-
        // dependent. The bar chart still shows import vs export via bar
        // position (above/below the baseline), just no longer via color.
        title(dc, "GRID", BRAND_ORANGE);
        mainMetric(dc, signedKwNumber(_model.gridKw), "kW");

        drawBars(dc, _model.gridHistory, 3.5, 263, 32, BRAND_ORANGE, true);
        bottomPair(dc, "EXPORTED", kwhNumber(_model.exportedTodayKwh), "kWh",
            "IMPORTED", kwhNumber(_model.importedTodayKwh), "kWh");
    }

    // Single-line rows (dot + label left, value right). Values are kept
    // short deliberately: a long combined string (e.g. battery % plus its
    // charge rate) is wide enough at this font to run into the label on
    // its left - the full charge-rate detail lives on the Battery page.
    function drawList(dc) {
        var batteryColor = _model.batteryKw < 0 ? BATTERY_VIOLET : BATTERY_CHARGE_GREY;

        listRow(dc, 66, "SOLAR", kwNumber(_model.solarKw), "kW", SOLAR_COLOR);
        listRow(dc, 138, "HOME", kwNumber(_model.homeKw), "kW", HOME_COLOR);
        listRow(dc, 210, "GRID", signedKwNumber(_model.gridKw), "kW", BRAND_ORANGE);
        listRow(dc, 282, "BATTERY", _model.batteryPct.format("%d") + "%", "", batteryColor);
    }

    function listRow(dc, y, label, number, unit, color) {
        var w = dc.getWidth();
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillCircle(99, y + 18, 5);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(117, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        drawSplitUnit(dc, w - 96, y, number, unit, Graphics.FONT_TINY, Graphics.FONT_XTINY,
            Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        // + 47 (FONT_TINY height, the taller of the two) + 5px gap.
        dc.drawLine(92, y + 52, w - 92, y + 52);
    }

    function drawConnection(dc) {
        var w = dc.getWidth();
        var cx = w / 2;
        var color = _online ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;

        title(dc, "CONNECTION", color);

        // Centered in the gap between the title (ends y=116) and ONLINE
        // (starts y=193): circle spans 2*32+7=71px, so cy=116+((77-71)/2)+32=155.
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(7);
        dc.drawCircle(cx, 155, 32);
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, 193, Graphics.FONT_MEDIUM, _online ? "ONLINE" : "OFFLINE", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        // 193 + 61 (FONT_MEDIUM height) + 4px gap.
        dc.drawText(cx, 258, Graphics.FONT_XTINY, _online ? "server reachable" : "using cached data", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawRoundedRectangle(137, 303, 180, 40, 18);
        dc.drawText(cx, 305, Graphics.FONT_XTINY, _loading ? "UPDATING..." : "REFRESH", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function title(dc, label, color) {
        var w = dc.getWidth();
        dc.setColor(color, Graphics.COLOR_BLACK);
        // HEADER_LINE_Y (55) + 8px gap, so the title's own top clears the
        // brand underline instead of starting inside its row.
        dc.drawText(w / 2, 63, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Value and unit on one line (e.g. "4.21 kW", unit smaller/dimmer) -
    // keeping them as two separate lines left no vertical room for the bar
    // chart and bottom stat row that follow (see the file header comment on
    // real font heights).
    function mainMetric(dc, number, unit) {
        var w = dc.getWidth();
        var cx = w / 2;
        // 63 (title offset) + 53 (FONT_SMALL height) + 9px gap.
        drawSplitUnit(dc, cx, 125, number, unit, Graphics.FONT_MEDIUM, Graphics.FONT_XTINY,
            Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawBars(dc, values, maxAbs, baselineY, maxH, color, signed) {
        var left = SAFE_LEFT;
        var right = SAFE_RIGHT;
        var chartW = right - left;
        var count = values.size();
        if (count <= 0) { return; }

        var gap = 2;
        var barW = ((chartW - ((count - 1) * gap)) / count).toNumber();
        if (barW < 3) { barW = 3; }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(left, baselineY, right, baselineY);

        for (var i = 0; i < count; i += 1) {
            var v = values[i].toFloat();
            var h = ((v.abs() / maxAbs) * maxH).toNumber();
            if (h < 2) { h = 2; }
            if (h > maxH) { h = maxH; }

            var x = left + i * (barW + gap);
            dc.setColor(color, Graphics.COLOR_BLACK);
            // Direction (e.g. grid import vs export) is shown by bar
            // position - above or below the baseline - not by color; both
            // sides share the series' one color, matching the web app's
            // single-color-per-category convention.
            if (signed && v > 0) {
                dc.fillRectangle(x, baselineY, barW, h);
            } else {
                dc.fillRectangle(x, baselineY - h, barW, h);
            }
        }
    }

    // Stacked-area day graph spanning the full day (0h-24h fixed on the
    // x-axis, not just however many samples exist): PV-to-battery stacked
    // under PV-to-home, total production traced on top - same composition
    // as the web app's Graph tab "Power Production" chart
    // (web/src/graph/GraphTab.jsx), ported to a midnight-to-now x-axis
    // with a pulsing "now" dot instead of that chart's trailing-24h window
    // (which has no such marker - see the comment on drawSolarDayGraph's
    // call site). `totalValues`/`battValues` are assumed evenly spaced
    // samples from midnight up to now, so they're plotted between the
    // left edge (0h) and a "now" x position derived from the actual clock
    // - not the chart's right edge - leaving the remaining hours blank.
    function drawSolarDayGraph(dc, totalValues, battValues, maxAbs, baselineY, maxH) {
        var left = SAFE_LEFT;
        var right = SAFE_RIGHT;
        var chartW = right - left;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(left, baselineY, right, baselineY);

        var clock = System.getClockTime();
        var nowFrac = (clock.hour + (clock.min / 60.0)) / 24.0;
        var nowX = left + (nowFrac * chartW);

        var count = totalValues.size();
        if (battValues.size() < count) { count = battValues.size(); }
        if (count <= 0) { return; }

        var xs = new [count];
        var battYs = new [count];
        var totalYs = new [count];
        for (var i = 0; i < count; i += 1) {
            xs[i] = (count > 1) ? (left + ((i.toFloat() / (count - 1)) * (nowX - left))) : nowX;
            var battVal = battValues[i];
            var totalVal = totalValues[i];
            // Guard against stale/inconsistent data (battery portion
            // shouldn't ever exceed total production for the same sample).
            if (battVal.toFloat().abs() > totalVal.toFloat().abs()) { battVal = totalVal; }
            battYs[i] = dayGraphY(battVal, maxAbs, baselineY, maxH);
            totalYs[i] = dayGraphY(totalVal, maxAbs, baselineY, maxH);
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
            dc.setPenWidth(3);
            for (var j = 1; j < count; j += 1) {
                dc.drawLine(xs[j - 1], totalYs[j - 1], xs[j], totalYs[j]);
            }
            dc.setPenWidth(1);
        }

        // Pulsing "now" marker on the total-production line: radius
        // oscillates 3-9px via _pulsePhase, ticked by a dedicated timer
        // (see onPulseTick) independent of the data-refresh cycle.
        var lastX = xs[count - 1];
        var lastY = totalYs[count - 1];
        var pulseR = 6 + (3 * Math.sin(_pulsePhase));
        dc.setColor(SOLAR_COLOR, Graphics.COLOR_BLACK);
        dc.fillCircle(lastX, lastY, pulseR);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(lastX, lastY, 3);
        dc.setColor(SOLAR_COLOR, Graphics.COLOR_BLACK);
        dc.fillCircle(lastX, lastY, 2);
    }

    function dayGraphY(value, maxAbs, baselineY, maxH) {
        var h = ((value.toFloat().abs() / maxAbs) * maxH).toNumber();
        if (h < 0) { h = 0; }
        if (h > maxH) { h = maxH; }
        return baselineY - h;
    }

    // Label and value stay on separate stacked lines (narrow text, centered
    // independently per side - this is what keeps left/right columns from
    // ever colliding, unlike combining them onto one wide line). The gap
    // between the two lines is the full FONT_XTINY height, not a fraction
    // of it (see the file header comment on real font heights). The value's
    // unit renders dimmer than its number, same as everywhere else - at
    // this font (already the device's smallest) they're necessarily the
    // same size, so color is the only remaining way to set them apart.
    function bottomPair(dc, leftLabel, leftNumber, leftUnit, rightLabel, rightNumber, rightUnit) {
        bottomPairAt(dc, 275, leftLabel, leftNumber, leftUnit, rightLabel, rightNumber, rightUnit);
    }

    function bottomPairAt(dc, y, leftLabel, leftNumber, leftUnit, rightLabel, rightNumber, rightUnit) {
        var w = dc.getWidth();
        var leftX = 145;
        var rightX = w - 145;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(leftX, y, Graphics.FONT_XTINY, leftLabel, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, y, Graphics.FONT_XTINY, rightLabel, Graphics.TEXT_JUSTIFY_CENTER);

        // + 37 (FONT_XTINY height) + 4px gap.
        drawSplitUnit(dc, leftX, y + 41, leftNumber, leftUnit, Graphics.FONT_XTINY, Graphics.FONT_XTINY,
            Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
        drawSplitUnit(dc, rightX, y + 41, rightNumber, rightUnit, Graphics.FONT_XTINY, Graphics.FONT_XTINY,
            Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function kw(v) {
        return v.format("%.2f") + " kW";
    }

    function kwNumber(v) {
        return v.format("%.2f");
    }

    function signedKw(v) {
        if (v > 0) { return "+" + v.format("%.2f") + " kW"; }
        return v.format("%.2f") + " kW";
    }

    function signedKwNumber(v) {
        if (v > 0) { return "+" + v.format("%.2f"); }
        return v.format("%.2f");
    }

    function kwh(v) {
        return v.format("%.1f") + " kWh";
    }

    function kwhNumber(v) {
        return v.format("%.1f");
    }

    function minutes(total) {
        var h = total / 60;
        var m = total % 60;
        if (h > 0) { return h.format("%d") + "h " + m.format("%02d") + "m"; }
        return m.format("%d") + "m";
    }
}
