using Toybox.Graphics;
using Toybox.WatchUi;
using Toybox.Timer;
using Toybox.System;
using Toybox.Math;

class HomePowerView extends WatchUi.View {
    const PAGE_COUNT = 6;

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
        if (_page == 5 || !_online) {
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
        else if (_page == 4) { drawList(dc); }
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

        var statusColor = _online ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_RED;
        drawScaledText(dc, w / 2, FOOTER_STATUS_Y + 2, status, Graphics.FONT_XTINY, statusColor, 0.74, Graphics.TEXT_JUSTIFY_CENTER);

        // Eight small dots are much safer on a round screen than a wide
        // "1/8  up/down pages" string near the lower bezel.
        var firstX = (w / 2) - 42;
        for (var i = 0; i < PAGE_COUNT; i += 1) {
            dc.setColor(i == _page ? Graphics.COLOR_WHITE : Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
            dc.fillCircle(firstX + (i * 12), FOOTER_DOTS_Y, i == _page ? 4 : 2);
        }
    }

    // Renders text at `font`'s native size into an offscreen buffer, then
    // blits it scaled down by `scale` - genuinely smaller than any text
    // font this device exposes (FONT_XTINY, 37px, is the floor - see the
    // file header comment), not just dimmer/lighter. Only worth the
    // extra cost (an allocation + a blit per call) for text that doesn't
    // change every frame, like the footer status line.
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
        drawDirectionalLabel(dc, leftX, row2Y, "GRID", exporting, BRAND_ORANGE, 0x4A3018, false);
        overviewValue(dc, leftX, row2Y, kwNumber(_model.gridKw.abs()), "kW");

        // Charge/discharge rate (2026, user request: "how much you pull
        // from battery too" - the Live tab equivalent on the phone app
        // shows this rate, not just the charge %, which stays available
        // on the Battery page). Battery always stays its identity violet
        // now (2026, user request: "follow the color convention" - no
        // more muted grey while charging). Discharging still positions
        // the triangle before the word, pointing away (energy leaving);
        // charging positions it after the word but points it BACK at
        // "BATTERY" instead (2026, user report: charging is the dominant
        // state and the arrow should visually flow INTO the battery, not
        // away from it).
        var charging = _model.batteryKw > 0.02;
        var discharging = _model.batteryKw < -0.02;
        if (charging || discharging) {
            drawDirectionalLabel(dc, rightX, row2Y, "BATTERY", discharging, BATTERY_VIOLET, 0x3A2550, charging);
        } else {
            overviewLabel(dc, rightX, row2Y, "BATTERY", BATTERY_VIOLET);
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
    // controls which SIDE of the word the triangle sits on (true = left/
    // before, false = right/after). `pointInward` controls which way its
    // apex faces, independent of that side: false points it further away
    // from the word (Grid's "<- GRID" / "GRID ->" - both read as flow
    // leaving toward the thing named); true points it back at the word
    // instead (2026, user report: Battery's charging arrow pointed away
    // from "BATTERY" when charging is the dominant state and should
    // visually flow INTO it - discharging's "away" reading was already
    // correct, so only charging needed the apex flipped, not the side).
    function drawDirectionalLabel(dc, x, y, word, triangleBefore, color, dimColor, pointInward) {
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
        var apexRight = pointInward ? triangleBefore : !triangleBefore;
        var points;
        if (apexRight) {
            points = [
                [cxTri + (triLen / 2), cyTri],
                [cxTri - (triLen / 2), cyTri - triHalfH],
                [cxTri - (triLen / 2), cyTri + triHalfH],
            ];
        } else {
            points = [
                [cxTri - (triLen / 2), cyTri],
                [cxTri + (triLen / 2), cyTri - triHalfH],
                [cxTri + (triLen / 2), cyTri + triHalfH],
            ];
        }
        dc.fillPolygon(points);
    }

    // Same idea as drawDirectionalLabel, sized for a page title (FONT_SMALL)
    // instead of the compact Overview cells (FONT_XTINY) - used by the
    // Battery page's title to show charge/discharge direction there too.
    // `pointInward` - see drawDirectionalLabel's comment.
    function drawDirectionalTitle(dc, label, triangleBefore, color, dimColor, pointInward) {
        var w = dc.getWidth();
        var cx = w / 2;
        var y = 63;
        var wordW = dc.getTextWidthInPixels(label, Graphics.FONT_SMALL);
        var gap = 10;
        var triLen = 17;
        var triHalfH = 9;
        var totalW = wordW + gap + triLen;
        var startX = cx - (totalW / 2);
        var cyTri = y + 26; // vertical middle of the FONT_SMALL text box

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
        dc.drawText(wordX, y, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_LEFT);

        var t = (Math.sin(_pulsePhase) + 1) / 2;
        dc.setColor(lerpColor(dimColor, color, t), Graphics.COLOR_BLACK);
        var apexRight = pointInward ? triangleBefore : !triangleBefore;
        var points;
        if (apexRight) {
            points = [
                [cxTri + (triLen / 2), cyTri],
                [cxTri - (triLen / 2), cyTri - triHalfH],
                [cxTri - (triLen / 2), cyTri + triHalfH],
            ];
        } else {
            points = [
                [cxTri - (triLen / 2), cyTri],
                [cxTri + (triLen / 2), cyTri - triHalfH],
                [cxTri + (triLen / 2), cyTri + triHalfH],
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
        // No separate current-value line here - the pulsing dot's position
        // on the graph already shows it, and the freed space goes to the
        // graph instead (2026, user request: same treatment as Home below).
        // Y-axis scale was a hardcoded 4.8 ceiling (2026, user report:
        // "a lot of space unused for the visualization... make other y
        // axis resolution") - a quiet/cloudy day's real peak sits well
        // under that, so the curve never reached anywhere near the top.
        // Derived from today's actual peak instead, so the chart always
        // uses its full height regardless of how big that peak is. 10%
        // headroom keeps the peak off the very top pixel; a 0.5 kW floor
        // keeps a near-zero night from blowing the scale up around noise.
        var peak = maxOf(_model.solarHistory);
        var maxAbs = peak * 1.1;
        if (maxAbs < 0.5) { maxAbs = 0.5; }
        // 116 (title bottom) + 3px gap.
        drawSolarDayGraph(dc, _model.solarHistory, _model.solarBatteryHistory, maxAbs, 263, 144);
        bottomPair(dc, "TODAY", kwhNumber(_model.solarTodayKwh), "kWh", "PEAK", kwNumber(peak), "kW");
    }

    // Highest value in a history array, 0.0 for an empty one - used for
    // the Solar page's "PEAK" stat and both pages' dynamic Y-axis scale
    // (today's highest hourly sample).
    function maxOf(values) {
        var m = 0.0;
        for (var i = 0; i < values.size(); i += 1) {
            var v = values[i].toFloat();
            if (v > m) { m = v; }
        }
        return m;
    }

    function drawHome(dc) {
        title(dc, "HOME", HOME_COLOR);
        // No separate current-value line here - "NOW" in the bottom row
        // already shows it, and the freed space goes to the bars instead.
        // Same dynamic Y-axis scale as Solar, derived from today's actual
        // peak hourly consumption instead of a hardcoded 3.0 ceiling.
        var maxAbs = maxOf(_model.homeHistory) * 1.1;
        if (maxAbs < 0.5) { maxAbs = 0.5; }
        // 116 (title bottom) + 3px gap.
        drawHomeStackedBars(dc, _model.homeHistory, _model.homeFromGridHistory,
            _model.homeFromBatteryHistory, maxAbs, 263, 144);
        bottomPair(dc, "TODAY", kwhNumber(_model.homeTodayKwh), "kWh", "NOW", kwNumber(_model.homeKw), "kW");
    }

    function drawBattery(dc) {
        var w = dc.getWidth();
        var cx = w / 2;

        var charging = _model.batteryKw > 0.02;
        var discharging = _model.batteryKw < -0.02;

        // Title carries the same pulsing direction triangle as Overview's
        // Battery cell (2026, user request: "like you did with grid") -
        // always violet now, triangle pointing INTO the word while
        // charging (see drawDirectionalLabel's comment - same fix as
        // Overview's Battery cell, both reported together).
        if (charging || discharging) {
            drawDirectionalTitle(dc, "BATTERY", discharging, BATTERY_VIOLET, 0x3A2550, charging);
        } else {
            title(dc, "BATTERY", BATTERY_VIOLET);
        }

        // kWh equivalent of the charge % (2026, user request: "I need it
        // also in kWh", later: "write the value bigger") - derived
        // client-side from capacity * pct, no new backend field needed.
        // Dimmer than the percent (still secondary to it) but sized up
        // from the original 0.5, vertically centered against it the same
        // way the List page's per-row "kWh" suffix is.
        var currentKwh = _model.batteryCapacityKwh * _model.batteryPct / 100.0;
        var pctText = _model.batteryPct.format("%d") + "%";
        var kwhText = " · " + currentKwh.format("%.1f") + " kWh";
        var pctW = dc.getTextWidthInPixels(pctText, Graphics.FONT_MEDIUM);
        var battKwhScale = 0.72;
        var battKwhW = (dc.getTextWidthInPixels(kwhText, Graphics.FONT_XTINY) * battKwhScale).toNumber();
        var pctStartX = cx - ((pctW + battKwhW) / 2);
        var pctNumH = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var battKwhH = (dc.getFontHeight(Graphics.FONT_XTINY) * battKwhScale).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(pctStartX, 116, Graphics.FONT_MEDIUM, pctText, Graphics.TEXT_JUSTIFY_LEFT);
        drawScaledText(dc, pctStartX + pctW, 116 + ((pctNumH - battKwhH) / 2), kwhText, Graphics.FONT_XTINY,
            Graphics.COLOR_LT_GRAY, battKwhScale, Graphics.TEXT_JUSTIFY_LEFT);

        // Low/high SOC thresholds, genuinely smaller than any real text
        // font via drawScaledText (see its own comment) - a full XTINY
        // row wouldn't fit the vertical budget here alongside everything
        // else this page needs. LOW sits over the bar's left edge (where
        // its floor tick is), HIGH over the right edge (its ceiling tick).
        // 116 (percent offset) + 61 (FONT_MEDIUM height) + 2px gap.
        drawScaledText(dc, SAFE_LEFT, 179, "LOW " + _model.batteryFloorPct.format("%d") + "%",
            Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, 0.55, Graphics.TEXT_JUSTIFY_LEFT);
        drawScaledText(dc, SAFE_RIGHT, 179, "HIGH " + _model.batteryMaxPct.format("%d") + "%",
            Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, 0.55, Graphics.TEXT_JUSTIFY_RIGHT);

        // Horizontal fill bar instead of a circular gauge - the arc-angle
        // direction semantics on this device didn't behave as documented
        // (a "280 degree clockwise from top" sweep rendered as a small
        // sliver instead), so this reuses the same plain rectangle-fill
        // approach already proven by drawBars elsewhere in this file. This
        // shows state of charge, not direction, so it stays the battery's
        // identity violet regardless of charge/discharge. Floor/ceiling
        // ticks mark the low/high thresholds labeled above.
        var barY = 206;
        var barH = 16;
        var barW = SAFE_RIGHT - SAFE_LEFT;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawRoundedRectangle(SAFE_LEFT, barY, barW, barH, 6);
        var fillW = (barW * _model.batteryPct) / 100;
        dc.setColor(BATTERY_VIOLET, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(SAFE_LEFT, barY, fillW, barH, 6);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.setPenWidth(2);
        var floorX = SAFE_LEFT + ((barW * _model.batteryFloorPct) / 100);
        dc.drawLine(floorX, barY - 4, floorX, barY + barH + 4);
        var maxX = SAFE_LEFT + ((barW * _model.batteryMaxPct) / 100);
        dc.drawLine(maxX, barY - 4, maxX, barY + barH + 4);
        dc.setPenWidth(1);

        // Always violet now (2026, user request - no more grey while
        // charging, matches the title/Overview cell above).
        // 206 + 16 (bar height) + 9px gap.
        drawSplitUnit(dc, cx, 231, signedKwNumber(_model.batteryKw), "kW", Graphics.FONT_MEDIUM, Graphics.FONT_XTINY,
            BATTERY_VIOLET, Graphics.TEXT_JUSTIFY_CENTER);

        // Time to the applicable limit for the CURRENT direction - "to
        // full" while charging, "to empty" (reaching the low-SOC floor)
        // while discharging (2026, user request). Idle keeps showing "TO
        // FULL" (its existing default) since there's no discharge rate to
        // project an empty-time from.
        var timeLabel = discharging ? "TO EMPTY" : "TO FULL";
        var timeVal = discharging ? _model.batteryMinutesToEmpty : _model.batteryMinutesToFull;
        // 231 + 61 (FONT_MEDIUM height) + 4px gap.
        bottomPairAt(dc, 296, timeLabel, minutes(timeVal), "",
            "CAPACITY", kwhNumber(_model.batteryCapacityKwh), "kWh");
    }

    // Today's consumption-by-source breakdown, matching the web app's
    // Dashboard "today" tile (2026, user request): total consumption,
    // produced, then Grid/PV direct/From battery/To battery/To grid each
    // with their kWh (and, except To grid - which the web tile doesn't
    // percentage either - a % computed here from the kWh figures already
    // provided, no separate percentage fields needed from the backend).
    // From/To battery share one "BATTERY" label with a small triangle
    // instead of separate words, the same direction-via-triangle idea
    // used on Overview/Battery - down for "from" (flowing out), up for
    // "to" (flowing in).
    function drawList(dc) {
        var w = dc.getWidth();
        var cx = w / 2;

        title(dc, "TODAY", Graphics.COLOR_WHITE);

        // 116 (title bottom) + 3px gap. "kWh" sits AFTER the number,
        // vertically centered against it (2026, user request - not
        // bottom-aligned like before, and not stacked underneath either)
        // via the same measure-both-then-center-the-pair trick, with the
        // unit's y nudged so its (shorter) scaled bitmap's midpoint lines
        // up with the number's midpoint instead of sharing its top.
        var totalNum = kwhNumber(_model.homeTodayKwh);
        var totalNumW = dc.getTextWidthInPixels(totalNum, Graphics.FONT_SMALL);
        var unitScale = 0.55;
        var unitW = (dc.getTextWidthInPixels(" kWh", Graphics.FONT_XTINY) * unitScale).toNumber();
        var totalStartX = cx - ((totalNumW + unitW) / 2);
        var numH = dc.getFontHeight(Graphics.FONT_SMALL);
        var unitH = (dc.getFontHeight(Graphics.FONT_XTINY) * unitScale).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(totalStartX, 119, Graphics.FONT_SMALL, totalNum, Graphics.TEXT_JUSTIFY_LEFT);
        drawScaledText(dc, totalStartX + totalNumW, 119 + ((numH - unitH) / 2), " kWh", Graphics.FONT_XTINY,
            Graphics.COLOR_LT_GRAY, unitScale, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(SOLAR_COLOR, Graphics.COLOR_BLACK);
        dc.fillCircle(SAFE_LEFT + 4, 190, 4);
        // 119 + 53 (FONT_SMALL height) + 4px gap.
        drawScaledText(dc, SAFE_LEFT + 14, 176, kwhNumber(_model.solarTodayKwh) + " kWh produced",
            Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, 0.78, Graphics.TEXT_JUSTIFY_LEFT);

        // Percentages only where they add up to a sensible whole - Grid +
        // PV direct + From battery is "where today's consumption came
        // from" (2026, user request: the other two rows are production
        // allocation, a different base, confusing side by side with these).
        var home = _model.homeTodayKwh;
        var gridPct = pct(_model.importedTodayKwh, home);
        var pvPct = pct(_model.solarDirectTodayKwh, home);
        var fromBattPct = pct(_model.batteryDischargedTodayKwh, home);

        var rowY = 212;
        var rowStep = 31;
        // Grid uses todayRowGrid (triangle AFTER the word, matching the
        // Overview page's own Grid cell - "GRID ->" importing / "GRID <-"
        // exporting). Battery keeps the triangle in the shared left
        // marker column (todayRowTriangle) alongside the plain dot rows.
        todayRowGrid(dc, rowY, false, BRAND_ORANGE, _model.importedTodayKwh, gridPct);
        rowY += rowStep;
        todayRow(dc, rowY, "direct PV", SOLAR_COLOR, _model.solarDirectTodayKwh, pvPct);
        rowY += rowStep;
        todayRowTriangle(dc, rowY, "BATT", false, BATTERY_VIOLET, _model.batteryDischargedTodayKwh, fromBattPct);
        rowY += rowStep;
        todayRowTriangle(dc, rowY, "BATT", true, BATTERY_CHARGE_GREY, _model.batteryChargedTodayKwh, "");
        rowY += rowStep;
        todayRowGrid(dc, rowY, true, BRAND_ORANGE, _model.exportedTodayKwh, "");
    }

    // kWh as a % of `base` (home consumption for most rows, today's total
    // production for "to battery" - matches the web app's own "% of
    // production" wording there). "" when base isn't usable, rather than
    // a misleading 0%.
    function pct(value, base) {
        if (base == null || base <= 0 || value == null) { return ""; }
        // Round to nearest, not truncate - matches the web app's
        // Math.round(value/base*100) exactly (Dashboard.jsx).
        return (((value / base * 100) + 0.5).toNumber()) + "%";
    }

    function todayRow(dc, y, label, color, kwhValue, pctText) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillCircle(SAFE_LEFT + 4, y + 12, 4);
        todayRowText(dc, y, label, kwhValue, pctText);
    }

    // Triangle sits at the exact same marker spot todayRow's plain dot
    // does - only which way it points changes, label and value stay at
    // their usual fixed positions. `charging` = points right, "towards"
    // the label that follows (charging the battery, exporting to grid -
    // flowing INTO the thing named); false = points left, "outwards" away
    // from it (discharging, importing - flowing OUT of it).
    function todayRowTriangle(dc, y, label, charging, color, kwhValue, pctText) {
        var cxTri = SAFE_LEFT + 4;
        var cyTri = y + 10;
        var triLen = 9;
        var triHalfH = 5;

        dc.setColor(color, Graphics.COLOR_BLACK);
        var points;
        if (charging) {
            points = [[cxTri + (triLen / 2), cyTri], [cxTri - (triLen / 2), cyTri - triHalfH], [cxTri - (triLen / 2), cyTri + triHalfH]];
        } else {
            points = [[cxTri - (triLen / 2), cyTri], [cxTri + (triLen / 2), cyTri - triHalfH], [cxTri + (triLen / 2), cyTri + triHalfH]];
        }
        dc.fillPolygon(points);
        todayRowText(dc, y, label, kwhValue, pctText);
    }

    // Grid's own row style: the triangle sits AFTER the word "GRID"
    // (matching the Overview page's own Grid cell - "GRID ->" importing
    // / "GRID <-" exporting - 2026, user request for consistency between
    // the two views), not in the shared left marker column the dot/
    // triangle rows use. The label still starts at the SAME x as every
    // other row's label (SAFE_LEFT+14) so the names stay in one column
    // (2026, user request) - only the triangle's position differs.
    function todayRowGrid(dc, y, exporting, color, kwhValue, pctText) {
        var labelX = SAFE_LEFT + 14;
        var labelScale = 0.62;
        drawScaledText(dc, labelX, y, "GRID", Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, labelScale, Graphics.TEXT_JUSTIFY_LEFT);

        var labelW = (dc.getTextWidthInPixels("GRID", Graphics.FONT_XTINY) * labelScale).toNumber();
        var gap = 6;
        var triLen = 9;
        var triHalfH = 5;
        var cxTri = labelX + labelW + gap + (triLen / 2);
        var cyTri = y + 10;

        dc.setColor(color, Graphics.COLOR_BLACK);
        var points;
        if (exporting) {
            points = [[cxTri - (triLen / 2), cyTri], [cxTri + (triLen / 2), cyTri - triHalfH], [cxTri + (triLen / 2), cyTri + triHalfH]];
        } else {
            points = [[cxTri + (triLen / 2), cyTri], [cxTri - (triLen / 2), cyTri - triHalfH], [cxTri - (triLen / 2), cyTri + triHalfH]];
        }
        dc.fillPolygon(points);

        todayValueText(dc, y, kwhValue, pctText);
    }

    function todayRowText(dc, y, label, kwhValue, pctText) {
        drawScaledText(dc, SAFE_LEFT + 14, y, label, Graphics.FONT_XTINY, Graphics.COLOR_LT_GRAY, 0.62, Graphics.TEXT_JUSTIFY_LEFT);
        todayValueText(dc, y, kwhValue, pctText);
    }

    // Three fixed right-justified columns, reserved the same for every
    // row regardless of whether that row actually has a percentage - the
    // number's column always ends at `numberRightX`, so digit-count
    // differences between rows never shift it (2026, user report: "the
    // last two have the kWs under the percentages"). "kWh" always
    // follows the number, smaller/dimmer (2026, user request), in its
    // own reserved slot; the percentage, when present, gets the
    // outermost slot.
    function todayValueText(dc, y, kwhValue, pctText) {
        var numScale = 0.58;
        var unitScale = 0.42;
        var pctScale = 0.46;

        var pctColW = (dc.getTextWidthInPixels("100%", Graphics.FONT_TINY) * pctScale).toNumber() + 6;
        var unitColW = (dc.getTextWidthInPixels(" kWh", Graphics.FONT_TINY) * unitScale).toNumber() + 4;
        var unitRightX = SAFE_RIGHT - pctColW;
        var numberRightX = unitRightX - unitColW;

        // "kWh" is a shorter scaled bitmap than the number (drawScaledText
        // always blits from the TOP), so top-aligning both at the same y
        // leaves the unit looking pinned to the number's top instead of
        // centered on it (2026, user report) - nudge the unit down by half
        // the height difference to vertically center it against the number.
        var numH = (dc.getFontHeight(Graphics.FONT_TINY) * numScale).toNumber();
        var unitH = (dc.getFontHeight(Graphics.FONT_TINY) * unitScale).toNumber();
        var unitY = y + ((numH - unitH) / 2);

        drawScaledText(dc, numberRightX, y, kwhValue.format("%.2f"), Graphics.FONT_TINY, Graphics.COLOR_WHITE,
            numScale, Graphics.TEXT_JUSTIFY_RIGHT);
        drawScaledText(dc, unitRightX, unitY, " kWh", Graphics.FONT_TINY, Graphics.COLOR_LT_GRAY,
            unitScale, Graphics.TEXT_JUSTIFY_RIGHT);
        if (!pctText.equals("")) {
            drawScaledText(dc, SAFE_RIGHT, y, pctText, Graphics.FONT_TINY, Graphics.COLOR_WHITE,
                pctScale, Graphics.TEXT_JUSTIFY_RIGHT);
        }
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
        // 63 (title offset) + 53 (FONT_SMALL height) + 7px gap, nudged up
        // 2px further per user request.
        drawSplitUnit(dc, cx, 121, number, unit, Graphics.FONT_SMALL, Graphics.FONT_XTINY,
            Graphics.COLOR_WHITE, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // 24 fixed hourly slots (not just however many samples exist - matches
    // the Solar day graph's reasoning: future hours stay visibly blank
    // instead of the chart being squeezed to however much of the day has
    // happened). Each hour's bar is stacked grid (base) + battery (middle)
    // + solar (top, the remainder: total - grid - battery) - the same
    // visual language as the web app's Dashboard "consumption by source"
    // stacked bars, per-hour instead of per-day (2026, user request).
    function drawHomeStackedBars(dc, totalValues, gridValues, battValues, maxAbs, baselineY, maxH) {
        var left = SAFE_LEFT;
        var right = SAFE_RIGHT;
        var chartW = right - left;
        var slots = 24;
        var gap = 1;
        var slotW = ((chartW - ((slots - 1) * gap)) / slots).toNumber();
        if (slotW < 2) { slotW = 2; }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(left, baselineY, right, baselineY);

        var count = totalValues.size();
        var gridCount = gridValues.size();
        var battCount = battValues.size();
        var hours = slots < count ? slots : count;

        for (var i = 0; i < hours; i += 1) {
            var total = totalValues[i].toFloat().abs();
            // Nearest-neighbor resample grid/batt onto totalValues' own
            // index range - same fix as the Solar graph's battery band:
            // these can be a different (e.g. still-demo-fallback) length
            // than totalValues, and indexing position-for-position would
            // silently zero out every hour past the shorter array's end
            // instead of scaling across the full range.
            var gridIdx = (hours > 1 && gridCount > 1)
                ? Math.round((i.toFloat() / (hours - 1)) * (gridCount - 1)).toNumber()
                : 0;
            var battIdx = (hours > 1 && battCount > 1)
                ? Math.round((i.toFloat() / (hours - 1)) * (battCount - 1)).toNumber()
                : 0;
            var gridV = (gridCount > 0) ? gridValues[gridIdx].toFloat().abs() : 0.0;
            var battV = (battCount > 0) ? battValues[battIdx].toFloat().abs() : 0.0;
            // Guard against stale/inconsistent data the same way the Solar
            // graph does - the two parts can't add up to more than total.
            if (gridV > total) { gridV = total; }
            if (battV > total - gridV) { battV = total - gridV; }
            var solarV = total - gridV - battV;
            if (solarV < 0) { solarV = 0.0; }

            var x = left + (i * (slotW + gap));
            var gridH = ((gridV / maxAbs) * maxH).toNumber();
            var battH = ((battV / maxAbs) * maxH).toNumber();
            var solarH = ((solarV / maxAbs) * maxH).toNumber();
            var stackH = gridH + battH + solarH;
            if (stackH > maxH) {
                // Clamp the whole stack proportionally rather than letting
                // it overshoot maxH (possible once rounding each piece up
                // separately).
                var fix = maxH.toFloat() / stackH;
                gridH = (gridH * fix).toNumber();
                battH = (battH * fix).toNumber();
                solarH = (solarH * fix).toNumber();
            }

            var y = baselineY;
            if (gridH > 0) {
                dc.setColor(BRAND_ORANGE, Graphics.COLOR_BLACK);
                dc.fillRectangle(x, y - gridH, slotW, gridH);
                y -= gridH;
            }
            if (battH > 0) {
                dc.setColor(BATTERY_VIOLET, Graphics.COLOR_BLACK);
                dc.fillRectangle(x, y - battH, slotW, battH);
                y -= battH;
            }
            if (solarH > 0) {
                dc.setColor(SOLAR_COLOR, Graphics.COLOR_BLACK);
                dc.fillRectangle(x, y - solarH, slotW, solarH);
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

        // `count` is driven by totalValues alone - the total production
        // line and "now" dot must always use every real point it has.
        // battValues can be a different length (e.g. still the static
        // demo fallback while the backend doesn't send this field yet -
        // see WATCH.readme follow-up 2) and gets nearest-neighbor
        // resampled onto the same x-grid instead of clamping totalValues
        // down to it, which previously silently discarded the most
        // recent real hours whenever the two arrays' lengths differed.
        var count = totalValues.size();
        if (count <= 0) { return; }
        var battCount = battValues.size();

        var xs = new [count];
        var battYs = new [count];
        var totalYs = new [count];
        for (var i = 0; i < count; i += 1) {
            xs[i] = (count > 1) ? (left + ((i.toFloat() / (count - 1)) * (nowX - left))) : nowX;
            var totalVal = totalValues[i];
            var battVal = 0.0;
            if (battCount > 0) {
                var battIdx = (count > 1 && battCount > 1)
                    ? Math.round((i.toFloat() / (count - 1)) * (battCount - 1)).toNumber()
                    : 0;
                battVal = battValues[battIdx];
            }
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
