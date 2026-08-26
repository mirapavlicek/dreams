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

    //: Odkud je dojezd elektrokola: přímo z kola, dopočítaný ze stavu jeho
    //: baterie (přes ANT+ nebo Bluetooth), nebo jen odhad z ujetých kilometrů.
    const ASSIST_FROM_BIKE = 0;
    const ASSIST_FROM_BATTERY = 1;
    const ASSIST_FROM_BLE = 2;
    const ASSIST_ESTIMATED = 3;

    //: Kdo počítá dojezd elektrokola. Bosch, DJI ani Shimano po ANT+ LEV
    //: nemluví a Connect IQ se k jejich datům nedostane; novější Edge je ale
    //: umí nativně. V tom případě nemá smysl vedle skutečných čísel přístroje
    //: ukazovat vlastní odhad - palubovka místo toho e-bike vynechá a ani
    //: neotevírá kanály, které by stejně nic nepřinesly.
    const EBIKE_OWN = 0;
    const EBIKE_NATIVE = 1;

    var mEbikeSource as Lang.Number = EBIKE_OWN;
    var mFullRangeKm as Lang.Float = 90.0;
    var mBatteryWh as Lang.Float = 0.0;
    var mShowWeather = true;
    var mUseMap = true;
    var mCockpitStyle = true;
    var mUseLev as Lang.Boolean = true;
    //: Posílat kolu příkazy, ne jen poslouchat. Ve výchozím stavu vypnuté:
    //: je to zásah do stroje, který jede, a chování se mezi značkami liší.
    var mControlLev as Lang.Boolean = false;
    var mLevDeviceNumber as Lang.Number = 0;
    var mLev as RideLev or Null = null;
    var mBleName as Lang.String = "";
    var mBle as RideBle or Null = null;
    var mTrack = null;
    var mLatitudeScale = 1.0;

    function initialize() as Void {
        if (mTrack == null) {
            mTrack = [];
        }
        reloadSettings();
        openSensors();
    }

    function reloadSettings() as Void {
        if (!(Application has :Properties)) {
            return;
        }
        var source = Application.Properties.getValue("ebikeSource");
        if (source instanceof Lang.Number && source != mEbikeSource) {
            mEbikeSource = source;
            closeSensors();
        }
        var range = Application.Properties.getValue("assistFullRangeKm");
        if (range instanceof Lang.Number && range > 0) {
            mFullRangeKm = range.toFloat();
        }
        var capacity = Application.Properties.getValue("assistBatteryWh");
        if (capacity instanceof Lang.Number && capacity >= 0) {
            mBatteryWh = capacity.toFloat();
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

        var useLev = Application.Properties.getValue("useLevSensor");
        if (useLev instanceof Lang.Boolean) {
            mUseLev = useLev;
        }
        var control = Application.Properties.getValue("controlLev");
        if (control instanceof Lang.Boolean) {
            mControlLev = control;
        }
        var deviceNumber = Application.Properties.getValue("levDeviceNumber");
        if (deviceNumber instanceof Lang.Number && deviceNumber >= 0) {
            if (deviceNumber != mLevDeviceNumber) {
                mLevDeviceNumber = deviceNumber;
                closeSensors();
            }
        }
        if (!mUseLev) {
            closeSensors();
        }

        var bleName = Application.Properties.getValue("bleBatteryName");
        if (bleName instanceof Lang.String && !bleName.equals(mBleName)) {
            mBleName = bleName;
            closeBle();
        }
    }

    // --- ANT+ kanál elektrokola ---------------------------------------------

    //! Kanál otevíráme jen když ho uživatel chce a přístroj ANT umí. Když ho
    //! zabral někdo jiný (na jednom kanálu může viset jen jedna aplikace),
    //! zůstane null a dojezd se odhaduje.
    function openSensors() as Void {
        openLev();
        openBle();
    }

    function closeSensors() as Void {
        closeLev();
        closeBle();
    }

    //! Řeší si dojezd elektrokola přístroj sám? Pak do toho palubovka nemluví.
    function ebikeNative() as Lang.Boolean {
        return mEbikeSource == EBIKE_NATIVE;
    }

    function openLev() as Void {
        if (ebikeNative() || !mUseLev || mLev != null || !(Toybox has :Ant)) {
            return;
        }
        try {
            var sensor = new RideLev(mLevDeviceNumber);
            sensor.open();
            mLev = sensor;
        } catch (exception) {
            mLev = null;
        }
    }

    function closeLev() as Void {
        if (mLev == null) {
            return;
        }
        try {
            mLev.shutdown();
        } catch (exception) {
            // Kanál už mohl spadnout sám, na tom nesejde.
        }
        mLev = null;
    }

    //! Bluetooth se zapíná jen vyplněným jménem kola - skenování stojí baterii
    //! a kolům s ANT+ profilem LEV není k ničemu.
    function openBle() as Void {
        if (ebikeNative() || mBleName.length() == 0 || mBle != null ||
            !(Toybox has :BluetoothLowEnergy)) {
            return;
        }
        try {
            var sensor = new RideBle(mBleName);
            if (sensor.start()) {
                mBle = sensor;
            }
        } catch (exception) {
            mBle = null;
        }
    }

    function closeBle() as Void {
        if (mBle == null) {
            return;
        }
        try {
            mBle.stop();
        } catch (exception) {
            // Spojení mohlo mezitím spadnout, na tom nesejde.
        }
        mBle = null;
    }

    //! Tik z obrazovky: po Bluetooth se o hodnotu musíme čas od času říct sami.
    function poll() as Void {
        if (mBle != null) {
            mBle.poll();
        }
    }

    //! Kolo, které zrovna mluví. Jinak null a všechno se odhaduje.
    function lev() as RideLev or Null {
        if (mLev == null || !mLev.connected()) {
            return null;
        }
        return mLev;
    }

    //! Chce uživatel mapu z paměti přístroje, nebo mu stačí drobečková stopa?
    function mapEnabled() as Lang.Boolean {
        return mUseMap;
    }

    //: Proč místo mapy koukáš na drobečkovou stopu. Nastavuje to aplikace,
    //: datové pole mapu nemá vůbec a nechává tu null.
    var mMapNote as Lang.String or Null = null;

    function setMapNote(note as Lang.String or Null) as Void {
        mMapNote = note;
    }

    function mapNote() as Lang.String or Null {
        return mMapNote;
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
    // Dojezd bereme v tomhle pořadí:
    //   1. přímo z kola - stránka 2 profilu LEV, kolo počítá s vlastní
    //      spotřebou a profilem trasy, stejné číslo ukazuje i Edge sám,
    //   2. ze stavu baterie kola - když kolo dojezd neposílá, spočítáme ho
    //      z procent a spotřeby ve Wh/km (nebo z nastaveného dojezdu na plnou),
    //   3. odhad z ujetých kilometrů - když se s kolem nemluví vůbec.
    //
    // Který zdroj se povedl, hlásí assistSource(); kreslení pak k odhadu
    // připisuje poznámku, aby se nezaměnil s měřením.

    //! Procenta baterie ze standardní BLE služby, když ji kolo nabízí.
    function bleBatteryPercent() as Lang.Number or Null {
        return mBle == null ? null : mBle.batteryPercent();
    }

    function assistSource() as Lang.Number {
        var bike = lev();
        if (bike != null) {
            if (bike.rangeKm() != null) {
                return ASSIST_FROM_BIKE;
            }
            if (bike.batteryPercent() != null) {
                return ASSIST_FROM_BATTERY;
            }
        }
        return bleBatteryPercent() == null ? ASSIST_ESTIMATED : ASSIST_FROM_BLE;
    }

    //! Je dojezd měřený kolem, nebo jen náš odhad?
    function assistMeasured() as Lang.Boolean {
        return assistSource() != ASSIST_ESTIMATED;
    }

    function assistRangeKm() {
        var bike = lev();
        if (bike != null) {
            var reported = bike.rangeKm();
            if (reported != null) {
                return reported;
            }
            var soc = bike.batteryPercent();
            if (soc != null) {
                return rangeFromBattery(soc, bike.consumptionWhPerKm());
            }
        }
        var blePercent = bleBatteryPercent();
        if (blePercent != null) {
            // Přes BLE známe jen procenta, spotřebu ne - ta by musela z kola.
            return rangeFromBattery(blePercent, null);
        }
        var remaining = mFullRangeKm - distanceKm();
        return remaining > 0.0 ? remaining : 0.0;
    }

    //! Kolik ještě ujedeme na zbývající procenta. Se známou kapacitou baterie
    //! a spotřebou to je fyzika, jinak jen poměrná část dojezdu na plnou.
    function rangeFromBattery(percent, consumption) {
        if (mBatteryWh > 0.0 && consumption != null && consumption > 0.0) {
            return (mBatteryWh * percent / 100.0) / consumption;
        }
        return mFullRangeKm * percent / 100.0;
    }

    function assistBatteryPercent() {
        var bike = lev();
        if (bike != null) {
            var soc = bike.batteryPercent();
            if (soc != null) {
                return soc;
            }
        }
        var blePercent = bleBatteryPercent();
        if (blePercent != null) {
            return blePercent;
        }
        if (mFullRangeKm <= 0.0) {
            return 0;
        }
        var remaining = mFullRangeKm - distanceKm();
        if (remaining < 0.0) {
            remaining = 0.0;
        }
        return (remaining / mFullRangeKm * 100.0).toNumber();
    }

    //! Stupeň asistence z kola, nebo null když ho neposílá.
    function assistLevel() {
        var bike = lev();
        return bike == null ? null : bike.assistLevel();
    }

    // --- ovládání asistence --------------------------------------------------

    //! Smí se kolu posílat? Jen když to uživatel zapnul, kolo mluví a hlásí,
    //! kolik stupňů má - bez toho není o co opřít horní mez.
    function canControlAssist() as Lang.Boolean {
        if (!mControlLev || ebikeNative()) {
            return false;
        }
        var bike = lev();
        return bike != null && bike.assistLevel() != null && bike.totalAssistModes() != null;
    }

    //! Posune asistenci o krok nahoru nebo dolů. Strop je počet stupňů, které
    //! kolo hlásí ve stránce 5; vyšší číslo by profil sice přenesl, ale kolo
    //! by ho stejně oříznulo.
    function stepAssist(delta as Lang.Number) as Lang.Boolean {
        if (!canControlAssist()) {
            return false;
        }
        var bike = lev();
        var current = bike.requestedAssist();
        if (current == null) {
            current = bike.assistLevel();
        }
        var maximum = bike.totalAssistModes();
        var wanted = current + delta;
        if (wanted < 0) {
            wanted = 0;
        }
        if (wanted > maximum) {
            wanted = maximum;
        }
        if (wanted == current) {
            return false;
        }
        return bike.requestAssist(wanted);
    }

    //! Stupeň, na který čekáme - kreslení ho ukáže jinak než potvrzený.
    function pendingAssist() as Lang.Number or Null {
        var bike = lev();
        return bike == null ? null : bike.requestedAssist();
    }

    //! Režim asistence tak, jak mu říká výrobce - Giant hlásí ECO, ACTIVE nebo
    //! SPORT, Fazua BREEZE až ROCKET. U neznámé značky zbude číslo stupně,
    //! a když kolo hlásí i počet svých režimů, tak "ASIST 3/5".
    function assistModeText() as Lang.String or Null {
        var bike = lev();
        if (bike == null) {
            return null;
        }
        var name = bike.assistModeName();
        if (name != null) {
            return name;
        }
        var level = bike.assistLevel();
        if (level == null) {
            return null;
        }
        var total = bike.totalAssistModes();
        if (total != null && total > 0) {
            return "ASIST " + level.toString() + "/" + total.toString();
        }
        return "ASIST " + level.toString();
    }

    //! Popisek k baterii kola: měřená hodnota se doplní režimem asistence,
    //! odhad se přizná.
    function assistBatteryLabel() as Lang.String {
        var source = assistSource();
        if (source == ASSIST_ESTIMATED) {
            return "E-BIKE · ODHAD";
        }
        if (source == ASSIST_FROM_BLE) {
            return "E-BIKE · BLE";
        }
        var mode = assistModeLabel();
        return mode == null ? "E-BIKE" : "E-BIKE · " + mode;
    }

    //! Režim asistence pro popisek. Dokud kolo nepotvrdí náš požadavek, ukáže
    //! se se šipkou - ať je poznat, že jde o přání, ne o skutečnost.
    function assistModeLabel() as Lang.String or Null {
        var pending = pendingAssist();
        if (pending != null) {
            return "› " + assistNameFor(pending);
        }
        return assistModeText();
    }

    //! Jméno stupně tak, jak by ho kolo ukázalo, i pro stupeň, který teprve
    //! chceme nastavit.
    function assistNameFor(level as Lang.Number) as Lang.String {
        var bike = lev();
        if (bike != null) {
            var names = bike.expandedModeNames();
            if (names != null && level < names.size()) {
                return names[level] as Lang.String;
            }
        }
        return "ASIST " + level.toString();
    }

    //! Zkrácený popisek pro malé displeje: vedle procent baterie je "E-BIKE"
    //! zřejmé i bez psaní, důležitý je zdroj čísla.
    function assistShortLabel() as Lang.String {
        var pending = pendingAssist();
        if (pending != null) {
            return "› " + assistNameFor(pending);
        }
        var source = assistSource();
        if (source == ASSIST_ESTIMATED) {
            return "ODHAD";
        }
        if (source == ASSIST_FROM_BLE) {
            return "BLE";
        }
        var mode = assistModeText();
        return mode == null ? "E-BIKE" : mode;
    }

    //! Jednotka pod dojezdem - u odhadu je poctivé to napsat.
    function assistRangeUnit() as Lang.String {
        return assistMeasured() ? "km" : "km · odhad";
    }

    //! Poznámka pod dojezd tam, kde je na ni místo: odkud číslo je a jakou
    //! asistenci kolo zrovna drží.
    function assistNote() as Lang.String {
        var source = assistSource();
        if (source == ASSIST_ESTIMATED) {
            return "odhad";
        }
        if (source == ASSIST_FROM_BLE) {
            return "baterie přes BLE";
        }
        var mode = assistModeLabel();
        if (mode != null) {
            return mode;
        }
        return source == ASSIST_FROM_BIKE ? "přímo z kola" : "ze stavu baterie";
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
        addPoint(positionInfo.position.toDegrees() as Lang.Array<Lang.Double>);
    }

    //! Poloha z Activity.Info. Datové pole si vlastní odběr pozic zapnout
    //! nesmí - Position.enableLocationEvents() pro něj není dostupné - takže
    //! stopu skládá z toho, co mu přístroj podá při každém výpočtu.
    function onActivityLocation(location) as Void {
        if (location == null) {
            return;
        }
        addPoint(location.toDegrees() as Lang.Array<Lang.Double>);
    }

    function addPoint(degrees as Lang.Array<Lang.Double>) as Void {
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
