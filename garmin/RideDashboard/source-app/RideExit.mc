using Toybox.Lang;
using Toybox.WatchUi;

//! Odchod z aplikace s rozjetou jízdou.
//!
//! Zahodit nahranou jízdu tichým odchodem je to nejhorší, co může palubovka
//! udělat, takže se napřed zeptá. Když není co ukládat, odejde se rovnou.
module RideExit {

    //! @return true, když se událost zpracovala a přístroj nemá dělat nic dál
    function confirm() as Lang.Boolean {
        if (!RideRecord.pending()) {
            return false;
        }
        WatchUi.pushView(
            new WatchUi.Confirmation("Uložit jízdu?"),
            new RideExitDelegate(),
            WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}

class RideExitDelegate extends WatchUi.ConfirmationDelegate {

    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(response) {
        if (response == WatchUi.CONFIRM_YES) {
            RideRecord.save();
        } else {
            RideRecord.discard();
        }
        // Potvrzení se zavře samo; zbytek obrazovek pustíme až po něm.
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }
}
