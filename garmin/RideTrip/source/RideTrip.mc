using Toybox.Activity;
using Toybox.WatchUi;

//! Pruh s údaji o trase, dojezdem e-biku a stavem baterie.
//!
//! Kanál kola drží tenhle pruh, protože se v něm data z kola opravdu kreslí -
//! na ANT+ LEV smí viset jediný posluchač. Horní pruh (../RideField) ukazuje
//! rychlost a kadenci, kolo k tomu nepotřebuje.
class RideTrip extends WatchUi.DataField {

    function initialize() {
        DataField.initialize();
    }

    function compute(info as Activity.Info) as Void {
        RideData.poll();
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
