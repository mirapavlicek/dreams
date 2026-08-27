using Toybox.Activity;
using Toybox.WatchUi;

//! Palubovka nakreslená do plochy, kterou poli přidělí datová obrazovka.
//!
//! Kreslení je společné s aplikací (RideCockpit / RideChrome), takže se obě
//! varianty nemůžou rozejít. Dvě věci se ale liší:
//!
//! * Poloha chodí z `Activity.Info`, protože datové pole si vlastní odběr
//!   pozic zapnout nesmí - `Position.enableLocationEvents()` pro něj není
//!   dostupné a překladač ho rovnou odmítne.
//! * Mapa z paměti přístroje se nekreslí. Pole nemá vstup, kterým by se dalo
//!   mezi mapou a palubovkou přepínat, takže uprostřed zůstane drobečková
//!   stopa - kartografii stejně umí ukázat nativní mapová obrazovka vedle.
class RideField extends WatchUi.DataField {

    function initialize() {
        DataField.initialize();
    }

    //! Volá přístroj jednou za vteřinu s aktuálním stavem aktivity.
    function compute(info as Activity.Info) as Void {
        RideData.onActivityLocation(info.currentLocation);
    }

    function onUpdate(dc) as Void {
        if (RideTrouble.caught()) {
            RideTrouble.draw(dc);
            return;
        }
        try {
            // Pole nemusí dostat celou obrazovku. Na podílu datové obrazovky
            // by se návrh počítaný na celý displej jen svisle zmáčkl, takže se
            // místo něj kreslí mřížka metrik.
            if (RideCompact.band(dc)) {
                // Horní překryv původní palubovky - kadence v ciferníku,
                // tachometr, hodiny a pilulky s průměrem a maximem.
                RideCockpit.drawTopBand(dc);
            } else if (RideData.cockpitStyle()) {
                RideCockpit.draw(dc, false);
            } else {
                RideChrome.draw(dc, false);
            }
        } catch (exception) {
            RideTrouble.note("palubovka", exception);
            RideTrouble.draw(dc);
        }
    }
}
