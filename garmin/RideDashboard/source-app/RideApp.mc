using Toybox.Application;
using Toybox.WatchUi;

//! Konzole elektrokola.
//!
//! Palubovku na koukání dělají datová pole (../RideField a ../RideTrip) uvnitř
//! nativní aktivity, kde teče GPS i data o jízdě a vedle nich může svítit
//! nativní mapa přístroje. Jako druhá palubovka by tahle aplikace neměla co
//! nabídnout - samostatná Connect IQ aplikace stojí mimo aktivitu, takže by si
//! musela nahrávat vlastní jízdu, jen aby vůbec měla čísla.
//!
//! Má proto na starost to, co datové pole neumí: **ovládat kolo a ukázat, co
//! o sobě hlásí.** Pole nedostává vstup, takže z něj stupeň asistence přepnout
//! nejde.
class RideApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        try {
            RideData.initialize();
        } catch (exception) {
            RideTrouble.note("start", exception);
        }
    }

    function onStop(state) {
        RideData.closeSensors();
    }

    function getInitialView() {
        return [new RideBikeView(), new RideBikeDelegate()];
    }

    function onSettingsChanged() {
        RideData.reloadSettings();
        RideData.openSensors();
        WatchUi.requestUpdate();
    }
}
