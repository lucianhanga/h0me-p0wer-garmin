using Toybox.WatchUi;

class HomePowerDelegate extends WatchUi.BehaviorDelegate {
    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() {
        _view.nextPage();
        return true;
    }

    function onPreviousPage() {
        _view.previousPage();
        return true;
    }

    function onSelect() {
        _view.activate();
        return true;
    }
}
