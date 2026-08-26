using Toybox.Lang;
using Toybox.Timer;
using Toybox.WatchUi;

//! Stav přepínače mezi mapovou a drobečkovou palubovkou.
module RideMaps {

    //: Uživatel se z mapy vrátil zpět - sami už mu ji nevnucujeme.
    var mWanted as Lang.Boolean = true;
    //: Mapu se nepodařilo otevřít; podruhé to už nezkoušíme.
    var mBroken as Lang.Boolean = false;

    //! Mapové view existuje jen na jednotkách s kartografií v paměti.
    function available() as Lang.Boolean {
        return !mBroken && (WatchUi has :MapTrackView) as Lang.Boolean;
    }

    function setBroken() as Void {
        mBroken = true;
    }

    //! Proč se místo mapy kreslí drobečková stopa. Na přístroji je to jediné
    //! vodítko - ručně nahraná aplikace nemá kam vypsat log.
    function reason() as Lang.String or Null {
        if (mBroken) {
            return "mapa se neotevřela";
        }
        if (!(WatchUi has :MapTrackView)) {
            return "přístroj mapy neumí";
        }
        if (!RideData.mapEnabled()) {
            return "mapa vypnutá v nastavení";
        }
        return null;
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
        try {
            RideData.poll();
        } catch (exception) {
            RideTrouble.note("čtení senzorů", exception);
        }
        WatchUi.requestUpdate();
    }

    //! Mapová obrazovka je to jediné, co může na cizím přístroji selhat způsobem,
    //! na který nedohlédneme - kartografie je na každé jednotce jiná a chová se
    //! jinak než v simulátoru. Když se otevřít nedá, palubovka zůstane
    //! s drobečkovou stopou; přijít o mapu je lepší než přijít o celou aplikaci.
    function onOpenMap() as Void {
        mMapTimer = null;
        if (!RideMaps.wanted()) {
            RideData.setMapNote(RideMaps.reason());
            return;
        }
        try {
            var view = new RideMapView();
            WatchUi.pushView(view, new RideMapDelegate(view), WatchUi.SLIDE_IMMEDIATE);
            RideData.setMapNote(null);
        } catch (exception) {
            RideMaps.setWanted(false);
            RideMaps.setBroken();
            RideData.setMapNote("mapa se neotevřela");
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc) {
        if (RideTrouble.caught()) {
            RideTrouble.draw(dc);
            return;
        }
        try {
            if (RideData.cockpitStyle()) {
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

    function onMenu() {
        RideMenu.open();
        return true;
    }

    function onNextPage() {
        return RideAssist.step(1);
    }

    function onPreviousPage() {
        return RideAssist.step(-1);
    }
}

//! Asistence pod tlačítky nahoru a dolů, na obou obrazovkách stejně.
//!
//! Když ovládání není zapnuté nebo kolo nemluví, událost se nezpracuje
//! (vrátí false) a přístroj si s tlačítkem naloží po svém - to je lepší, než
//! ho tiše spolknout.
module RideAssist {

    function step(delta as Lang.Number) as Lang.Boolean {
        if (!RideData.canControlAssist()) {
            return false;
        }
        RideData.stepAssist(delta);
        WatchUi.requestUpdate();
        return true;
    }
}
