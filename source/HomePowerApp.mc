using Toybox.Application;

class HomePowerApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new HomePowerView();
        return [view, new HomePowerDelegate(view)];
    }
}
