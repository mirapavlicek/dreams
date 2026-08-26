using Toybox.Activity;
using Toybox.WatchUi;

//! Pruh s údaji o trase. Senzory kola neotevírá - ty drží první pole, a na
//! jednom ANT+ kanálu může viset jen jeden posluchač.
class RideTrip extends WatchUi.DataField {

    function initialize() {
        DataField.initialize();
    }

    function compute(info as Activity.Info) as Void {
    }

    function onUpdate(dc) as Void {
        if (RideTrouble.caught()) {
            RideTrouble.draw(dc);
            return;
        }
        try {
            // Spodní překryv původní palubovky - dojezd, do cíle, najeto,
            // stavový řádek a proužek baterie e-biku.
            RideCockpit.drawBottomBand(dc);
        } catch (exception) {
            RideTrouble.note("pruh s trasou", exception);
            RideTrouble.draw(dc);
        }
    }
}
