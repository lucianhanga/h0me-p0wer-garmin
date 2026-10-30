using Toybox.Background;
using Toybox.System;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Application;

// Runs outside the normal app lifecycle, woken by the temporal event
// HomePowerFaceApp schedules (see its scheduleNextRefresh) - this is the
// ONLY place a watch face is allowed to do a network fetch while not
// actively being viewed; a Timer in the view would not survive the watch
// going back to its low-power sleep state. Background.exit() hands the
// result to HomePowerFaceApp.onBackgroundData in the foreground context.
(:background)
class HomePowerFaceDelegate extends System.ServiceDelegate {
    function initialize() {
        System.ServiceDelegate.initialize();
    }

    // Application.Storage is available directly in the background
    // context (unlike most of Toybox), so this writes a marker
    // synchronously BEFORE the async network call, not via
    // Background.exit (which would end the process right here instead
    // of continuing to actually fetch). If the request then hangs or
    // never calls back for any reason, this marker still proves the OS
    // invoked the delegate at all - distinguishing "scheduling never
    // fires on this device" from "it fires but the request fails"
    // (2026, debugging a user report: real watch never shows anything
    // but "--:--", despite the exact same delegate code working every
    // time when manually triggered in the simulator).
    function onTemporalEvent() {
        Application.Storage.setValue("lastInvokedAt", System.getClockTime().hour.format("%02d") + ":" +
            System.getClockTime().min.format("%02d"));

        var headers = { "Accept" => "application/json" };
        if (!Config.API_TOKEN.equals("")) {
            headers.put("Authorization", "Bearer " + Config.API_TOKEN);
        }

        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(
            Config.API_URL,
            null,
            options,
            method(:onReceive)
        );
    }

    function onReceive(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or Null
    ) as Void {
        var result = { "responseCode" => responseCode };
        if (responseCode == 200 && data instanceof Lang.Dictionary) {
            result.put("data", data);
        }
        Background.exit(result);
    }
}
