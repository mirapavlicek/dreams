using Toybox.Activity;
using Toybox.Application;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;

//! Sbírá hodnoty pro dashboard. Vše, co Connect IQ nenabízí, se dopočítává
//! nebo vrací null - kreslení si s tím poradí a ukáže pomlčky.
module RideData {

    //: Kolik bodů stopy si držíme pro minimapu.
    const TRACK_CAPACITY = 150;

    var mFullRangeKm = 90.0;
    var mShowWeather = true;
    var mUseMap = true;
    var mCockpitStyle = true;
    var mTrack = null;
    var mLatitudeScale = 1.0;

    function initialize() as Void {
        if (mTrack == null) {
            mTrack = [];
        }
        reloadSettings();
    }

    function reloadSettings() as Void {
        if (!(Application has :Properties)) {
            return;
        }
        var range = Application.Properties.getValue("assistFullRangeKm");
        if (range instanceof Lang.Number && range > 0) {
            mFullRangeKm = range.toFloat();
        }
        var weather = Application.Properties.getValue("showWeather");
        if (weather instanceof Lang.Boolean) {
            mShowWeather = weather;
        }
        var useMap = Application.Properties.getValue("useMap");
        if (useMap instanceof Lang.Boolean) {
            mUseMap = useMap;
        }
        var style = Application.Properties.getValue("layoutStyle");
        if (style instanceof Lang.Number) {
            mCockpitStyle = style == 0;
        }
    }

    //! Chce uživatel mapu z paměti přístroje, nebo mu stačí drobečková stopa?
    function mapEnabled() as Lang.Boolean {
        return mUseMap;
    }

    //! Styl přístrojového štítu (mapa přes celou obrazovku) místo panelů.
    function cockpitStyle() as Lang.Boolean {
        return mCockpitStyle;
    }

    function info() {
        return Activity.getActivityInfo();
    }

    function floatOr(value, fallback) {
        if (value instanceof Lang.Number || value instanceof Lang.Float ||
            value instanceof Lang.Long || value instanceof Lang.Double) {
            return value.toFloat();
        }
        return fallback;
    }

    // --- rychlost -----------------------------------------------------------

    function speedKmh(value) {
        return floatOr(value, 0.0) * 3.6;
    }

    function speed() {
        var current = info();
        return current == null ? 0.0 : speedKmh(current.currentSpeed);
    }

    function averageSpeed() {
        var current = info();
        return current == null ? 0.0 : speedKmh(current.averageSpeed);
    }

    function maxSpeed() {
        var current = info();
        return current == null ? 0.0 : speedKmh(current.maxSpeed);
    }

    function cadence() {
        var current = info();
        if (current == null || !(current.currentCadence instanceof Lang.Number)) {
            return 0;
        }
        return current.currentCadence;
    }

    // --- vzdálenosti --------------------------------------------------------

    function distanceKm() {
        var current = info();
        return current == null ? 0.0 : floatOr(current.elapsedDistance, 0.0) / 1000.0;
    }

    //! Vrací null, dokud není načtená trasa - buňka pak ukáže pomlčky.
    function distanceToDestinationKm() {
        var current = info();
        if (current == null || current.distanceToDestination == null) {
            return null;
        }
        return floatOr(current.distanceToDestination, 0.0) / 1000.0;
    }

    //! Odhad příjezdu z průměrné rychlosti; bez pohybu nedává smysl.
    function etaString() {
        var remaining = distanceToDestinationKm();
        var average = averageSpeed();
        if (remaining == null || average < 1.0) {
            return "--:--";
        }
        var seconds = (remaining / average) * 3600.0;
        var arrival = Time.now().add(new Time.Duration(seconds.toNumber()));
        var parts = Time.Gregorian.info(arrival, Time.FORMAT_SHORT);
        return Lang.format("$1$:$2$", [parts.hour.format("%02d"), parts.min.format("%02d")]);
    }

    function ascent() {
        var current = info();
        if (current == null || !(current.totalAscent instanceof Lang.Number)) {
            return 0;
        }
        return current.totalAscent;
    }

    function descent() {
        var current = info();
        if (current == null || !(current.totalDescent instanceof Lang.Number)) {
            return 0;
        }
        return current.totalDescent;
    }

    //! Směr jízdy ve stupních (0 = sever).
    function heading() {
        var current = info();
        if (current == null) {
            return 0.0;
        }
        var radians = floatOr(current.currentHeading, 0.0);
        var degrees = radians * 180.0 / Math.PI;
        while (degrees < 0.0) {
            degrees += 360.0;
        }
        return degrees;
    }

    // --- elektrokolo --------------------------------------------------------
    //
    // Connect IQ nedává přístup k baterii elektrokola (ANT+ profil LEV není
    // v API), takže dojezd odhadujeme z ujeté vzdálenosti a dojezdu na plnou
    // baterii, který si uživatel nastaví. Je to odhad, ne měření.

    function assistRangeKm() {
        var remaining = mFullRangeKm - distanceKm();
        return remaining > 0.0 ? remaining : 0.0;
    }

    function assistBatteryPercent() {
        if (mFullRangeKm <= 0.0) {
            return 0;
        }
        var ratio = assistRangeKm() / mFullRangeKm;
        return (ratio * 100.0).toNumber();
    }

    function deviceBatteryPercent() {
        return System.getSystemStats().battery.toNumber();
    }

    // --- okolí --------------------------------------------------------------

    function temperature() {
        if (!mShowWeather || !(Toybox has :Weather)) {
            return null;
        }
        var conditions = Toybox.Weather.getCurrentConditions();
        if (conditions == null || !(conditions.temperature instanceof Lang.Number)) {
            return null;
        }
        return conditions.temperature;
    }

    function weatherCondition() {
        if (!mShowWeather || !(Toybox has :Weather)) {
            return null;
        }
        var conditions = Toybox.Weather.getCurrentConditions();
        return conditions == null ? null : conditions.condition;
    }

    function clockString() {
        var now = System.getClockTime();
        var hour = now.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour.format("%02d"), now.min.format("%02d")]);
    }

    function hasFix() {
        var current = info();
        if (current == null || !(current.currentLocationAccuracy instanceof Lang.Number)) {
            return false;
        }
        return current.currentLocationAccuracy >= Position.QUALITY_USABLE;
    }

    // --- stopa ---------------------------------------------------------------
    //
    // Každý bod je [x, šířka, délka]: x je délka zkrácená kosinem šířky pro
    // drobečkovou mapu, zbylá dvě čísla jsou surové stupně pro polyline nad
    // opravdovou mapou.

    function onPosition(positionInfo as Position.Info) as Void {
        if (positionInfo == null || positionInfo.position == null) {
            return;
        }
        var degrees = positionInfo.position.toDegrees() as Lang.Array<Lang.Double>;
        var latitude = degrees[0];
        var longitude = degrees[1];

        if (mTrack == null) {
            mTrack = [];
        }
        if (mTrack.size() == 0) {
            // Délku zkracujeme kosinem šířky, aby minimapa nebyla natažená.
            mLatitudeScale = Math.cos(latitude * Math.PI / 180.0);
        }
        mTrack.add([longitude * mLatitudeScale, latitude, longitude]);
        if (mTrack.size() > TRACK_CAPACITY) {
            mTrack = mTrack.slice(mTrack.size() - TRACK_CAPACITY, mTrack.size());
        }
    }

    function track() as Lang.Array {
        return (mTrack == null ? [] : mTrack) as Lang.Array;
    }
}
