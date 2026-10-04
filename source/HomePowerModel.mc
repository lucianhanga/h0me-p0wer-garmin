using Toybox.System;

class HomePowerModel {
    var solarKw = 4.21;
    var homeKw = 1.87;
    var gridKw = -2.34;
    var batteryPct = 78;
    var batteryKw = 1.20;
    var solarTodayKwh = 18.4;
    var homeTodayKwh = 22.6;
    var exportedTodayKwh = 18.1;
    var importedTodayKwh = 6.4;
    var batteryCapacityKwh = 14.2;
    var batteryMinutesToFull = 195;
    var updatedText = "--:--";

    var solarHistory = [0.4,0.7,1.1,1.8,2.6,3.4,4.0,4.4,4.6,4.5,4.2,3.8,3.0,2.1,1.2,0.5];
    var homeHistory = [1.2,1.6,1.3,1.1,1.0,1.2,1.4,1.7,2.3,2.6,2.2,1.8,1.7,1.5,1.4,1.3];
    var gridHistory = [-0.8,-1.1,-1.6,-2.1,-2.4,-2.8,-3.1,-3.0,-2.6,-2.2,-1.8,-1.2,-0.6,0.2,0.5,0.3];
    // Portion of solarHistory routed to the battery rather than the house,
    // same index/cadence as solarHistory - the Solar page's day graph
    // stacks this under the total production line (see WATCH.readme in
    // the backend repo: not sent by the live API yet, so this demo curve
    // is also the fallback when the field is absent).
    var solarBatteryHistory = [0.0,0.1,0.3,0.6,0.9,1.2,1.4,1.5,1.5,1.4,1.2,0.9,0.6,0.3,0.1,0.0];

    function initialize() {
        stampNow();
    }

    function stampNow() {
        var t = System.getClockTime();
        updatedText = t.hour.format("%02d") + ":" + t.min.format("%02d");
    }

    function updateDemo() {
        // Small deterministic movement so the UI feels live in the simulator.
        var t = System.getClockTime();
        var bump = (t.sec % 10).toFloat() / 100.0;
        solarKw = 4.15 + bump;
        homeKw = 1.82 + (bump / 2.0);
        gridKw = homeKw - solarKw;
        batteryPct = 78;
        batteryKw = 1.20;
        stampNow();
    }

    function applyDictionary(data) {
        solarKw = getFloat(data, "solar", solarKw);
        homeKw = getFloat(data, "home", homeKw);
        gridKw = getFloat(data, "grid", gridKw);
        batteryPct = getNumber(data, "battery", batteryPct);
        batteryKw = getFloat(data, "batteryPower", batteryKw);
        solarTodayKwh = getFloat(data, "solarToday", solarTodayKwh);
        homeTodayKwh = getFloat(data, "homeToday", homeTodayKwh);
        exportedTodayKwh = getFloat(data, "exportedToday", exportedTodayKwh);
        importedTodayKwh = getFloat(data, "importedToday", importedTodayKwh);
        batteryCapacityKwh = getFloat(data, "batteryCapacity", batteryCapacityKwh);
        batteryMinutesToFull = getNumber(data, "batteryMinutesToFull", batteryMinutesToFull);

        if (data.hasKey("solarHistory") && data["solarHistory"] != null) {
            solarHistory = data["solarHistory"];
        }
        if (data.hasKey("solarBatteryHistory") && data["solarBatteryHistory"] != null) {
            solarBatteryHistory = data["solarBatteryHistory"];
        }
        if (data.hasKey("homeHistory") && data["homeHistory"] != null) {
            homeHistory = data["homeHistory"];
        }
        if (data.hasKey("gridHistory") && data["gridHistory"] != null) {
            gridHistory = data["gridHistory"];
        }
        stampNow();
    }

    function getFloat(data, key, fallback) {
        if (!data.hasKey(key) || data[key] == null) { return fallback; }
        return data[key].toFloat();
    }

    function getNumber(data, key, fallback) {
        if (!data.hasKey(key) || data[key] == null) { return fallback; }
        return data[key].toNumber();
    }
}
