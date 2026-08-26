using Toybox.Lang;
using Toybox.Timer;
using Toybox.WatchUi;

//! Stav přepínače mezi mapovou a drobečkovou palubovkou.
module RideMaps {

    //: Uživatel se z mapy vrátil zpět - sami už mu ji nevnucujeme.
    var mWanted as Lang.Boolean = true;

    //! Mapové view existuje jen na jednotkách s kartografií v paměti.
    function available() as Lang.Boolean {
        return (WatchUi has :MapTrackView) as Lang.Boolean;
    }

    function wanted() as Lang.Boolean {
        return available() && mWanted && RideData.mapEnabled();
    }

    function setWanted(value as Lang.Boolean) as Void {
        mWanted = value;
    }
}

//! Palubovka s drobečkovou stopou místo mapy. Je to výchozí obrazovka
//! aplikace: Connect IQ neumí vrátit mapové view z getInitialView(), dá se jen
//! vystrčit přes pushView, takže mapa se otevírá odsud.
class RideView extends WatchUi.View {

    hidden var mTimer as Timer.Timer?;
    hidden var mMapTimer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        mTimer = new Timer.Timer();
        mTimer.start(method(:onTick), 1000, true);

        if (RideMaps.wanted()) {
            // Push až po dokreslení téhle obrazovky, ne uvnitř onShow.
            mMapTimer = new Timer.Timer();
            mMapTimer.start(method(:onOpenMap), 50, false);
        }
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
        if (mMapTimer != null) {
            mMapTimer.stop();
            mMapTimer = null;
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onOpenMap() as Void {
        mMapTimer = null;
        if (!RideMaps.wanted()) {
            return;
        }
        var view = new RideMapView();
        WatchUi.pushView(view, new RideMapDelegate(view), WatchUi.SLIDE_IMMEDIATE);
    }

    function onUpdate(dc) {
        RideChrome.draw(dc, false);
    }
}

//! Výběr přepne zpátky na mapu, pokud ji přístroj umí.
class RideDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView as RideView;

    function initialize(view as RideView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() {
        if (RideMaps.available()) {
            RideMaps.setWanted(true);
            mView.onOpenMap();
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }
}
