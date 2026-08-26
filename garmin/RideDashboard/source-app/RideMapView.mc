using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Position;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

//! Palubovka nad opravdovou mapou z paměti přístroje.
//!
//! MapTrackView vykresluje kartografii pod celou obrazovkou a sám se drží
//! aktuální polohy. setScreenVisibleArea() mapu neořízne - jen říká, na kterou
//! část obrazovky se má zaostřit a co ještě není zakryté naším rozhraním.
//! Všechno mimo mapové okno si tedy musíme překreslit sami, jinak by mapa
//! prosvítala pod ciferníky (viz vlákno "MapView" na fóru Connect IQ).
class RideMapView extends WatchUi.MapTrackView {

    hidden var mTimer as Timer.Timer?;
    //: Kolik bodů stopy už je v polyline - přerýsovává se, jen když přibyly.
    hidden var mTrackPoints as Lang.Number = 0;
    //: Než proběhne onLayout, nemá view plochu a na mapu se sahat nesmí.
    hidden var mReady as Lang.Boolean = false;

    //! Konstruktor mapu **nenastavuje**. `setScreenVisibleArea()` ani
    //! `setMapMode()` se nesmí volat na view, které ještě není připojené -
    //! skončí to "Unexpected Type Error", tedy pádem aplikace. Simulátor to
    //! přejde, protože kartografii jen předstírá, na přístroji ne.
    //! Obojí proto patří až do onLayout(), kdy view plochu opravdu má.
    function initialize() {
        MapTrackView.initialize();
    }

    //! Zaostří mapu tam, kde ji nepřekrývá palubovka.
    function applyWindow() as Void {
        if (!mReady) {
            return;
        }
        var rect = (RideData.cockpitStyle() ? RideLayout.cockpitMapRect() : RideLayout.mapRect())
            as Lang.Array;
        setScreenVisibleArea(rect[0] as Lang.Number, rect[1] as Lang.Number,
            rect[2] as Lang.Number, rect[3] as Lang.Number);
    }

    function onLayout(dc) {
        // onLayout volá systém až po pushView, takže sem try/catch kolem
        // otevírání mapy nedosáhne - vlastní ho tedy potřebuje.
        try {
            RideLayout.prepare(dc);
            mReady = true;
            applyWindow();
            setMapMode(WatchUi.MAP_MODE_PREVIEW);
        } catch (exception) {
            RideTrouble.note("nastavení mapy", exception);
        }
    }

    function onShow() {
        RideMaps.attach(self);
        // Styl se mohl mezitím změnit v nastavení, tak okno přepočítáme.
        applyWindow();
        mTimer = new Timer.Timer();
        mTimer.start(method(:onTick), 1000, true);
    }

    function onHide() {
        RideMaps.attach(null);
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
    }

    function onTick() as Void {
        try {
            RideRecord.publish();
            RideData.poll();
            updateTrack();
        } catch (exception) {
            RideTrouble.note("stopa nad mapou", exception);
        }
        WatchUi.requestUpdate();
    }

    //! Projetá stopa jako polyline nad mapou. Skládat ji každou vteřinu je
    //! zbytečně drahé, takže jen když od minule přibyly body.
    function updateTrack() as Void {
        var track = RideData.track();
        if (track.size() < 2 || track.size() == mTrackPoints) {
            return;
        }

        var polyline = new WatchUi.MapPolyline();
        polyline.setColor(RideLayout.color("accent") as Lang.Number);
        polyline.setWidth((RideLayout.s(RideLayout.number("map", "trackPen")) as Lang.Float).toNumber());
        for (var i = 0; i < track.size(); i += 1) {
            var point = track[i] as Lang.Array;
            polyline.addLocation(new Position.Location({
                :latitude => point[1] as Lang.Double,
                :longitude => point[2] as Lang.Double,
                :format => :degrees
            }));
        }
        setPolyline(polyline);
        mTrackPoints = track.size();
    }

    function isBrowsing() as Lang.Boolean {
        return getMapMode() == WatchUi.MAP_MODE_BROWSE;
    }

    //! V režimu procházení patří obrazovka mapě - palubovku schováme, ať se dá
    //! posouvat a zoomovat jako v nativní mapě.
    //!
    //! Přepíná se **jen režim**. Sáhnout kolem toho na `setScreenVisibleArea()`
    //! shodí aplikaci na "Unexpected Type Error" - a to v obou směrech, protože
    //! přepnutí režimu nedoběhne hned a mapa si mezitím plochu řídí sama.
    //! Zaostření se proto nastavuje jen v konstruktoru a v `onShow()`; přes
    //! procházení projde nedotčené, takže se po návratu mapa sama vrátí do okna
    //! mezi překryvy.
    function setBrowsing(browsing as Lang.Boolean) as Void {
        if (!mReady) {
            return;
        }
        setMapMode(browsing ? WatchUi.MAP_MODE_BROWSE : WatchUi.MAP_MODE_PREVIEW);
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        if (RideTrouble.caught()) {
            RideTrouble.draw(dc);
            return;
        }
        try {
            // Nejdřív mapa, pak naše rozhraní přes ni.
            MapView.onUpdate(dc);
            if (isBrowsing()) {
                return;
            }
            if (RideData.cockpitStyle()) {
                RideCockpit.draw(dc, true);
            } else {
                RideChrome.draw(dc, true);
            }
        } catch (exception) {
            RideTrouble.note("palubovka nad mapou", exception);
            RideTrouble.draw(dc);
        }
    }
}

//! Výběr přepne na mapu přes celou obrazovku, zpět se vrací o krok dál až na
//! palubovku s drobečkovou stopou.
class RideMapDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView as RideMapView;

    function initialize(view as RideMapView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() {
        RideRecord.toggle();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        if (mView.isBrowsing()) {
            mView.setBrowsing(false);
            return true;
        }
        RideMaps.setWanted(false);
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
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
