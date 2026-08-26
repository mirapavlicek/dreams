using Toybox.Application;
using Toybox.WatchUi;

//! Táž palubovka jako aplikace v ../RideDashboard, jen jako datové pole.
//!
//! Proč obojí: aplikace zabere celou obrazovku a přístroj pod ní schová své
//! vlastní datové obrazovky. Datové pole naopak v nativní aktivitě bydlí, takže
//! vedle něj můžou na téže obrazovce svítit údaje, na které Connect IQ nedosáhne
//! - hlavně e-bike data z Bosch Smart System. Za to platí tím, že nemá žádný
//! vstup: nejde v něm otevřít menu ani ovládat asistenci.
class RideFieldApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        RideData.initialize();
    }

    function onStop(state) {
        RideData.closeSensors();
    }

    function getInitialView() {
        return [new RideField()];
    }

    function onSettingsChanged() {
        RideData.reloadSettings();
        RideData.openSensors();
        WatchUi.requestUpdate();
    }
}
