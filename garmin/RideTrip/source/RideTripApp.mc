using Toybox.Application;
using Toybox.WatchUi;

//! Druhé datové pole: údaje o trase do pruhu pod mapou.
//!
//! Kreslení i data sdílí s ../RideDashboard, jen ukazuje jiné údaje než
//! RideField. Smysl dává ve dvojici: nahoře rychlost a kadence, uprostřed
//! nativní mapa přístroje, dole tohle.
class RideTripApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        RideData.reloadSettings();
    }

    function onStop(state) {
    }

    function getInitialView() {
        return [new RideTrip()];
    }

    function onSettingsChanged() {
        RideData.reloadSettings();
        WatchUi.requestUpdate();
    }
}
