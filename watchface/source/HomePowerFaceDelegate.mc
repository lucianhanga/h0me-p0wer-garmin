using Toybox.Background;
using Toybox.System;
using Toybox.Communications;
using Toybox.Lang;

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

    function onTemporalEvent() {
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
        if (responseCode == 200 && data instanceof Lang.Dictionary) {
            Background.exit(data);
        } else {
            Background.exit(null);
        }
    }
}
