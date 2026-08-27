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
        // Dojezd a baterie kola se kreslí tady, takže tenhle pruh drží ANT+
        // kanál - na LEV smí viset jediný posluchač.
        RideData.initialize();
    }

    function onStop(state) {
        RideData.closeSensors();
    }

    function getInitialView() {
        return [new RideTrip()];
    }

    function onSettingsChanged() {
        RideData.reloadSettings();
        RideData.openSensors();
        WatchUi.requestUpdate();
    }
}
