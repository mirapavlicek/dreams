using Toybox.Application;
using Toybox.Position;
using Toybox.WatchUi;

//! Jízdní dashboard pro Edge: tachometr s půlkruhem kadence, mapa uprostřed
//! obklopená čtyřmi metrikami a spodní lišta se stavem baterie, převýšením
//! a počasím.
class RideApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        RideData.initialize();
        if (Position has :enableLocationEvents) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function onStop(state) {
        if (Position has :enableLocationEvents) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        }
    }

    function onPosition(info as Position.Info) as Void {
        RideData.onPosition(info);
    }

    function getInitialView() {
        return [new RideView(), new RideDelegate()];
    }

    function onSettingsChanged() {
        RideData.reloadSettings();
        WatchUi.requestUpdate();
    }
}
