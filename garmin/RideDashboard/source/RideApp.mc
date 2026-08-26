using Toybox.Application;
using Toybox.Position;
using Toybox.WatchUi;

//! Jízdní dashboard pro Edge: tachometr s půlkruhem kadence, mapa uprostřed
//! obklopená čtyřmi metrikami a spodní lišta se stavem baterie, převýšením
//! a počasím.
//!
//! Mapová obrazovka (RideMapView) se otevírá z RideView - Connect IQ mapové
//! view z getInitialView() nepřijme.
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
        RideData.closeSensors();
    }

    function onPosition(info as Position.Info) as Void {
        RideData.onPosition(info);
    }

    function getInitialView() {
        var view = new RideView();
        return [view, new RideDelegate(view)];
    }

    function onSettingsChanged() {
        RideData.reloadSettings();
        RideData.openSensors();
        WatchUi.requestUpdate();
    }
}
