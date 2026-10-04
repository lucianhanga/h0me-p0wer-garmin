using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.Timer;
using Toybox.WatchUi;

class HomePowerService {
    var _view;
    var _model;
    var _timer;
    var _busy = false;

    function initialize(view, model) {
        _view = view;
        _model = model;
        _timer = new Timer.Timer();
    }

    function start() {
        refresh();
        _timer.start(method(:onTimer), Config.REFRESH_MS, true);
    }

    function stop() {
        _timer.stop();
    }

    function onTimer() {
        refresh();
    }

    function refresh() {
        if (Config.USE_DEMO_DATA) {
            _model.updateDemo();
            _view.setConnectionState(true, false);
            WatchUi.requestUpdate();
            return;
        }

        if (_busy) {
            return;
        }

        _busy = true;

        _view.setConnectionState(
            _view.isOnline(),
            true
        );

        WatchUi.requestUpdate();

        var options = {
            :method =>
                Communications.HTTP_REQUEST_METHOD_GET,

            :headers => {
                "Accept" => "application/json"
            },

            :responseType =>
                Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };

        Communications.makeWebRequest(
            Config.API_URL,
            null,
            options,
            method(:onResponse)
        );
    }

    function onResponse(
        responseCode as Lang.Number,
        data as Lang.Dictionary
            or Lang.String
            or PersistedContent.Iterator
            or Null
    ) as Void {

        _busy = false;

        if (
            responseCode == 200 &&
            data instanceof Lang.Dictionary
        ) {
            _model.applyDictionary(data);

            Application.Storage.setValue(
                "lastData",
                data
            );

            _view.setConnectionState(true, false);

        } else {

            var cached =
                Application.Storage.getValue(
                    "lastData"
                );

            if (cached instanceof Lang.Dictionary) {
                _model.applyDictionary(cached);
            }

            _view.setConnectionState(false, false);
        }

        WatchUi.requestUpdate();
    }
}
