using Toybox.Graphics;
using Toybox.WatchUi;

class HomePowerView extends WatchUi.View {
    const PAGE_COUNT = 8;

    // Layout tuned specifically for the 454x454 round AMOLED display used by
    // the Fenix 8 47 mm / 51 mm.  The important rule is that all large text
    // stays inside the wide middle portion of the circle; only small footer
    // elements are allowed near the lower edge.
    const SAFE_LEFT = 86;
    const SAFE_RIGHT = 368;
    const HEADER_LINE_Y = 42;
    const FOOTER_STATUS_Y = 344;
    const FOOTER_DOTS_Y = 378;

    var _page = 0;
    var _online = true;
    var _loading = false;
    var _model;
    var _service;

    function initialize() {
        View.initialize();
        _model = new HomePowerModel();
        _service = new HomePowerService(self, _model);
    }

    function onShow() {
        _service.start();
    }

    function onHide() {
        _service.stop();
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
        if (_page == 7 || !_online) {
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
        else if (_page == 5) { drawSummaryRing(dc); }
        else if (_page == 6) { drawList(dc); }
        else { drawConnection(dc); }

        drawFooter(dc);
    }

    function drawHeader(dc) {
        var w = dc.getWidth();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(w / 2, 14, Graphics.FONT_XTINY, "HOME POWER", Graphics.TEXT_JUSTIFY_CENTER);
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

    function drawOverview(dc) {
        var w = dc.getWidth();
        var cx = w / 2;
        var leftX = 143;
        var rightX = w - 143;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(cx, 70, cx, 292);
        dc.drawLine(92, 181, w - 92, 181);

        overviewCell(dc, leftX, 66, "SOLAR", kwNumber(_model.solarKw), "kW", Graphics.COLOR_YELLOW);
        overviewCell(dc, rightX, 66, "HOME", kwNumber(_model.homeKw), "kW", Graphics.COLOR_BLUE);

        var gridColor = _model.gridKw < 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE;
        overviewCell(dc, leftX, 184, "GRID", signedKwNumber(_model.gridKw), _model.gridKw < 0 ? "kW export" : "kW import", gridColor);
        overviewCell(dc, rightX, 184, "BATTERY", _model.batteryPct.format("%d") + "%", signedKw(_model.batteryKw), Graphics.COLOR_GREEN);
    }

    function overviewCell(dc, x, y, label, value, subValue, color) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillCircle(x, y + 7, 5);
        dc.drawText(x, y + 18, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(x, y + 46, Graphics.FONT_MEDIUM, value, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(x, y + 82, Graphics.FONT_XTINY, subValue, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawSolar(dc) {
        title(dc, "SOLAR", Graphics.COLOR_YELLOW);
        mainMetric(dc, kwNumber(_model.solarKw), "kW", "current production", Graphics.COLOR_YELLOW);
        drawBars(dc, _model.solarHistory, 4.8, 226, 48, Graphics.COLOR_YELLOW, false);
        bottomPair(dc, "TODAY", kwh(_model.solarTodayKwh), "PEAK", "4.6 kW");
    }

    function drawHome(dc) {
        title(dc, "HOME", Graphics.COLOR_BLUE);
        mainMetric(dc, kwNumber(_model.homeKw), "kW", "current consumption", Graphics.COLOR_BLUE);
        drawBars(dc, _model.homeHistory, 3.0, 226, 48, Graphics.COLOR_BLUE, false);
        bottomPair(dc, "TODAY", kwh(_model.homeTodayKwh), "NOW", kw(_model.homeKw));
    }

    function drawBattery(dc) {
        var w = dc.getWidth();
        var cx = w / 2;

        title(dc, "BATTERY", Graphics.COLOR_GREEN);

        // Keep the arc entirely below the title and leave clear vertical room
        // for the power value and the two bottom statistics.
        var cy = 143;
        var radius = 64;
        dc.setPenWidth(9);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, -45);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        var endDeg = 225 - ((270 * _model.batteryPct) / 100);
        dc.drawArc(cx, cy, radius, Graphics.ARC_COUNTER_CLOCKWISE, 225, endDeg);
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, 121, Graphics.FONT_MEDIUM, _model.batteryPct.format("%d") + "%", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 157, Graphics.FONT_XTINY, "state of charge", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        dc.drawText(cx, 202, Graphics.FONT_MEDIUM, signedKw(_model.batteryKw), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 235, Graphics.FONT_XTINY, _model.batteryKw >= 0 ? "charging" : "discharging", Graphics.TEXT_JUSTIFY_CENTER);

        bottomPairAt(dc, 266, "TO FULL", minutes(_model.batteryMinutesToFull), "CAPACITY", kwh(_model.batteryCapacityKwh));
    }

    function drawGrid(dc) {
        var color = _model.gridKw < 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE;
        title(dc, "GRID", color);
        mainMetric(dc, signedKwNumber(_model.gridKw), "kW", _model.gridKw < 0 ? "exporting" : "importing", color);

        // Signed chart uses a shorter amplitude so positive import bars never
        // collide with the summary row below it.
        drawBars(dc, _model.gridHistory, 3.5, 218, 38, color, true);
        bottomPair(dc, "EXPORTED", kwh(_model.exportedTodayKwh), "IMPORTED", kwh(_model.importedTodayKwh));
    }

    function drawSummaryRing(dc) {
        var w = dc.getWidth();
        var cx = w / 2;
        var cy = 184;
        var r = 105;
        var gridColor = _model.gridKw < 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE;

        dc.setPenWidth(8);
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 175, 103);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 85, 13);
        dc.setColor(gridColor, Graphics.COLOR_BLACK);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 355, 283);
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 265, 193);
        dc.setPenWidth(1);

        summaryCell(dc, 165, 116, "SOLAR", kwNumber(_model.solarKw), Graphics.COLOR_YELLOW);
        summaryCell(dc, 289, 116, "HOME", kwNumber(_model.homeKw), Graphics.COLOR_BLUE);
        summaryCell(dc, 165, 205, "GRID", signedKwNumber(_model.gridKw), gridColor);
        summaryCell(dc, 289, 205, "BAT", _model.batteryPct.format("%d") + "%", Graphics.COLOR_GREEN);
    }

    function summaryCell(dc, x, y, label, value, color) {
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(x, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(x, y + 29, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawList(dc) {
        var w = dc.getWidth();
        var gridColor = _model.gridKw < 0 ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE;

        listRow(dc, 78, "SOLAR", kw(_model.solarKw), Graphics.COLOR_YELLOW);
        listRow(dc, 137, "HOME", kw(_model.homeKw), Graphics.COLOR_BLUE);
        listRow(dc, 196, "GRID", signedKw(_model.gridKw), gridColor);
        listRow(dc, 255, "BATTERY", _model.batteryPct.format("%d") + "%  " + signedKw(_model.batteryKw), Graphics.COLOR_GREEN);
    }

    function listRow(dc, y, label, value, color) {
        var w = dc.getWidth();
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.fillCircle(99, y + 11, 5);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(117, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(w - 96, y + 22, Graphics.FONT_TINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawLine(92, y + 48, w - 92, y + 48);
    }

    function drawConnection(dc) {
        var w = dc.getWidth();
        var cx = w / 2;
        var color = _online ? Graphics.COLOR_GREEN : Graphics.COLOR_RED;

        title(dc, "CONNECTION", color);

        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.setPenWidth(7);
        dc.drawCircle(cx, 132, 32);
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, 176, Graphics.FONT_MEDIUM, _online ? "ONLINE" : "OFFLINE", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 214, Graphics.FONT_XTINY, _online ? "server reachable" : "using cached data", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawRoundedRectangle(137, 252, 180, 44, 18);
        dc.drawText(cx, 263, Graphics.FONT_XTINY, _loading ? "UPDATING..." : "REFRESH", Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 310, Graphics.FONT_XTINY, _loading ? "please wait" : "press START to refresh", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function title(dc, label, color) {
        var w = dc.getWidth();
        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(w / 2, 50, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function mainMetric(dc, value, unit, sub, color) {
        var w = dc.getWidth();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(cx, 88, Graphics.FONT_MEDIUM, value, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(cx, 122, Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(color, Graphics.COLOR_BLACK);
        dc.drawText(cx, 145, Graphics.FONT_XTINY, sub, Graphics.TEXT_JUSTIFY_CENTER);
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
            if (signed && v > 0) {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_BLACK);
                dc.fillRectangle(x, baselineY, barW, h);
            } else {
                dc.setColor(color, Graphics.COLOR_BLACK);
                dc.fillRectangle(x, baselineY - h, barW, h);
            }
        }
    }

    function bottomPair(dc, leftLabel, leftValue, rightLabel, rightValue) {
        bottomPairAt(dc, 268, leftLabel, leftValue, rightLabel, rightValue);
    }

    function bottomPairAt(dc, y, leftLabel, leftValue, rightLabel, rightValue) {
        var w = dc.getWidth();
        var leftX = 145;
        var rightX = w - 145;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(leftX, y, Graphics.FONT_XTINY, leftLabel, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, y, Graphics.FONT_XTINY, rightLabel, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.drawText(leftX, y + 29, Graphics.FONT_TINY, leftValue, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(rightX, y + 29, Graphics.FONT_TINY, rightValue, Graphics.TEXT_JUSTIFY_CENTER);
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

    function minutes(total) {
        var h = total / 60;
        var m = total % 60;
        if (h > 0) { return h.format("%d") + "h " + m.format("%02d") + "m"; }
        return m.format("%d") + "m";
    }
}
