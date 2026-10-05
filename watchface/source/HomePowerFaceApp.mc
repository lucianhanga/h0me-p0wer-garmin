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

    // Garmin enforces a hard 5-minute FLOOR on registerForTemporalEvent -
    // confirmed via Garmin's own developer forums (nothing shorter is
    // honored on real hardware, even though the simulator doesn't
    // enforce it the same way). The previous cold-start fix here asked
    // for 10 SECONDS, under that floor - almost certainly silently
    // rejected, which left onBackgroundData never getting called even
    // once on a real watch (2026, user report: "the values from the
    // watch do not update... there are some fixed values which do not
    // change" - confirmed root cause). MIN_REFRESH_SECONDS is that
    // floor, used for the cold-start registration below instead of a
    // too-fast guess.
    const MIN_REFRESH_SECONDS = 300;

    function onStart(state) {
        // Cold start (freshly installed, or relaunched before any
        // background fetch has ever landed) - get real data in as soon
        // as the platform allows (see MIN_REFRESH_SECONDS above)
        // instead of leaving the view showing its zero defaults for up
        // to the full REFRESH_MINUTES. Once data has landed at least
        // once, onBackgroundData's own scheduleNextRefresh() call takes
        // over for every refresh after this one.
        if (Application.Storage.getValue("lastData") == null) {
            Background.registerForTemporalEvent(Time.now().add(new Time.Duration(MIN_REFRESH_SECONDS)));
        } else {
            scheduleNextRefresh();
        }
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
    // `result` is now {"responseCode" => N, "data" => {...}?} rather
    // than the bare dictionary, so a failed/non-200 attempt is still
    // visible (2026, debugging: real watch stuck on "--:--" forever,
    // need to see WHY an attempt is failing, not just whether it
    // succeeded) - the view surfaces responseCode next to "updated" so
    // a failure reason is visible without a USB-tethered debug session.
    function onBackgroundData(result) {
        var clock = System.getClockTime();
        var nowText = clock.hour.format("%02d") + ":" + clock.min.format("%02d");

        if (result != null && result instanceof Lang.Dictionary) {
            if (result.hasKey("responseCode")) {
                Application.Storage.setValue("lastResponseCode", result["responseCode"]);
                Application.Storage.setValue("lastAttemptText", nowText);
            }
            if (result.hasKey("data")) {
                Application.Storage.setValue("lastData", result["data"]);
                // Stamped here, not read live in the view - this marks
                // when data actually arrived, not "now" (2026, user
                // request: "put a very small timestamp").
                Application.Storage.setValue("lastUpdateText", nowText);
            }
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
