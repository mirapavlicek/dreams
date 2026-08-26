using Toybox.Application;
using Toybox.Lang;
using Toybox.WatchUi;

//! Nastavení přímo v přístroji. Aplikace nahraná ručně (sideload) se
//! v Garmin Connect ani v Garmin Expressu neobjeví, takže jinam než sem se
//! uživatel při testování s nastavením nedostane. Hodnoty jdou do stejných
//! properties, které jinak plní telefon, takže obojí funguje vedle sebe.
module RideMenu {

    //: Kapacity, které se na kolech potkávají nejčastěji; nula = neznámá.
    var CAPACITIES as Lang.Array<Lang.Number> = [0, 300, 400, 500, 625, 750, 800];

    //: Dojezd na plnou baterii pro případ, že kolo nic nehlásí.
    var RANGES as Lang.Array<Lang.Number> = [40, 60, 80, 90, 100, 120, 140, 160];

    function open() as Void {
        var menu = new WatchUi.Menu2({:title => "Elektrokolo"});

        menu.addItem(new WatchUi.ToggleMenuItem("Dojezd e-biku",
            {:enabled => "počítat sama", :disabled => "nechat na přístroji"},
            :ebike, !RideData.ebikeNative(), null));
        menu.addItem(new WatchUi.ToggleMenuItem("Elektrokolo ANT+",
            {:enabled => "číst data z kola", :disabled => "jen odhad dojezdu"},
            :lev, RideData.mUseLev, null));
        menu.addItem(new WatchUi.ToggleMenuItem("Ovládat asistenci",
            {:enabled => "tlačítky nahoru a dolů", :disabled => "jen číst, nic neposílat"},
            :control, RideData.mControlLev, null));
        menu.addItem(new WatchUi.MenuItem("Spárovat kolo znovu",
            pairingLabel(), :pair, null));
        menu.addItem(new WatchUi.MenuItem("Kapacita baterie",
            capacityLabel(), :capacity, null));
        menu.addItem(new WatchUi.MenuItem("Dojezd na plnou",
            RideData.mFullRangeKm.format("%.0f") + " km", :range, null));

        WatchUi.pushView(menu, new RideMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function pairingLabel() as Lang.String {
        if (RideData.lev() != null) {
            var mode = RideData.assistModeText();
            if (mode == null) {
                return "kolo je spárované";
            }
            return "spárováno · " + mode;
        }
        if (RideData.mLevDeviceNumber == 0) {
            return "hledá kolo";
        }
        return "hledá ID " + RideData.mLevDeviceNumber.toString();
    }

    function capacityLabel() as Lang.String {
        return RideData.mBatteryWh <= 0.0 ? "neznámá" : RideData.mBatteryWh.format("%.0f") + " Wh";
    }

    function store(key as Lang.String, value as Lang.Boolean or Lang.Number) as Void {
        if (Application has :Properties) {
            Application.Properties.setValue(key, value);
        }
        RideData.reloadSettings();
        RideData.openSensors();
    }

    //! Další hodnota v kruhu - na kole se čísla ťukají hůř než přepínají.
    function next(values as Lang.Array<Lang.Number>, current as Lang.Number) as Lang.Number {
        for (var i = 0; i < values.size(); i += 1) {
            if (values[i] == current) {
                return values[(i + 1) % values.size()];
            }
        }
        return values[0];
    }
}

class RideMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :ebike) {
            // Zapnuto = palubovka si dojezd počítá sama, vypnuto = přebírá to
            // přístroj (Bosch a spol., na které Connect IQ nedosáhne).
            RideMenu.store("ebikeSource", (item as WatchUi.ToggleMenuItem).isEnabled()
                ? RideData.EBIKE_OWN : RideData.EBIKE_NATIVE);

        } else if (id == :lev) {
            RideMenu.store("useLevSensor", (item as WatchUi.ToggleMenuItem).isEnabled());

        } else if (id == :control) {
            RideMenu.store("controlLev", (item as WatchUi.ToggleMenuItem).isEnabled());

        } else if (id == :pair) {
            // Nula znamená "vezmi první kolo, které se ozve"; uložené ID se
            // tím zahodí, takže se dá přesednout na jiné kolo.
            RideData.closeSensors();
            RideMenu.store("levDeviceNumber", 0);
            item.setSubLabel(RideMenu.pairingLabel());

        } else if (id == :capacity) {
            RideMenu.store("assistBatteryWh",
                RideMenu.next(RideMenu.CAPACITIES, RideData.mBatteryWh.toNumber()));
            item.setSubLabel(RideMenu.capacityLabel());

        } else if (id == :range) {
            RideMenu.store("assistFullRangeKm",
                RideMenu.next(RideMenu.RANGES, RideData.mFullRangeKm.toNumber()));
            item.setSubLabel(RideData.mFullRangeKm.format("%.0f") + " km");
        }

        WatchUi.requestUpdate();
    }
}
