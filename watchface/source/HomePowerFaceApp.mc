using Toybox.Application;
using Toybox.Background;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

(:background)
class HomePowerFaceApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        // Make sure a refresh is always scheduled - covers both first
        // install (nothing scheduled yet) and the app being relaunched
        // after being force-closed mid-cycle.
        scheduleNextRefresh();
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [ new HomePowerFaceView() ];
    }

    // Registers HomePowerFaceDelegate as the background process Garmin
    // wakes for the temporal event scheduled below.
    function getServiceDelegate() {
        return [ new HomePowerFaceDelegate() ];
    }

    // Called in the FOREGROUND context once the background fetch
    // completes (see HomePowerFaceDelegate.onReceive's Background.exit).
    // Cache the raw dictionary for the view to read in onUpdate, wake the
    // face so it redraws immediately instead of waiting for the next
    // natural minute tick, and schedule the next refresh.
    function onBackgroundData(data) {
        if (data != null) {
            Application.Storage.setValue("lastData", data);
            // Stamped here, not read live in the view - this marks when
            // data actually arrived, not "now" (2026, user request: "put
            // a very small timestamp").
            var clock = System.getClockTime();
            Application.Storage.setValue("lastUpdateText",
                clock.hour.format("%02d") + ":" + clock.min.format("%02d"));
        }
        scheduleNextRefresh();
        WatchUi.requestUpdate();
    }

    function scheduleNextRefresh() {
        var next = Time.now().add(new Time.Duration(Config.REFRESH_MINUTES * 60));
        Background.registerForTemporalEvent(next);
    }

    function onSettingsChanged() {
        WatchUi.requestUpdate();
    }
}

function getApp() as HomePowerFaceApp {
    return Application.getApp() as HomePowerFaceApp;
}
