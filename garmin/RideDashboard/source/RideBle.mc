using Toybox.BluetoothLowEnergy;
using Toybox.Lang;
using Toybox.System;

//: Profil se v aplikaci registruje jen jednou za běh - podruhé by Connect IQ
//: vyhodil výjimku. Proto to hlídá proměnná mimo instanci: po změně nastavení
//: vznikne nová RideBle, ale registrace platí dál.
var gBleProfileRegistered as Lang.Boolean = false;

//! Záloha pro kola, která ANT+ profil LEV nevysílají: přečte procenta baterie
//! přes Bluetooth ze standardní služby Battery Service (0x180F).
//!
//! Dál než k procentům se z Connect IQ dostat nedá. Bosch, Shimano i DJI vozí
//! svoji telemetrii ve vlastních šifrovaných službách, které se bez klíčů
//! a párovacího tance přečíst nedají - tohle funguje jen na kolech (nebo
//! chytrých bateriích), která nabízejí standardní službu podle specifikace
//! Bluetooth. Když ji kolo nemá, nestane se nic a dojezd zůstane odhadem.
//!
//! Aplikace se v BLE chová jako centrála: hledá podle jména z nastavení,
//! spáruje se s prvním, které sedí, a přečte jedinou charakteristiku.
class RideBle extends BluetoothLowEnergy.BleDelegate {

    //: 0000180F-0000-1000-8000-00805F9B34FB a 00002A19-... ze základní
    //: šestnáctibitové řady Bluetooth SIG.
    const BATTERY_SERVICE = BluetoothLowEnergy.longToUuid(0x0000180F00001000L, 0x800000805F9B34FBL);
    const BATTERY_LEVEL = BluetoothLowEnergy.longToUuid(0x00002A1900001000L, 0x800000805F9B34FBL);

    //: Baterie se mění pomalu, ale hlásit se sama nemusí - takhle často si
    //: o hodnotu řekneme.
    const READ_INTERVAL_MS = 30000;

    var mName as Lang.String;
    var mDevice as BluetoothLowEnergy.Device or Null = null;
    var mPercent as Lang.Number or Null = null;
    var mReadAt as Lang.Number or Null = null;

    //! @param name část jména kola v Bluetooth, porovnává se bez ohledu na
    //!        velikost písmen
    function initialize(name as Lang.String) {
        BleDelegate.initialize();
        mName = name.toUpper();
    }

    function start() as Lang.Boolean {
        if (mName.length() == 0) {
            return false;
        }
        BluetoothLowEnergy.setDelegate(self);
        if (!$.gBleProfileRegistered) {
            try {
                BluetoothLowEnergy.registerProfile({
                    :uuid => BATTERY_SERVICE,
                    :characteristics => [{
                        :uuid => BATTERY_LEVEL,
                        :descriptors => [BluetoothLowEnergy.cccdUuid()]
                    }]
                });
                $.gBleProfileRegistered = true;
            } catch (exception) {
                return false;
            }
        }
        scan(true);
        return true;
    }

    function stop() as Void {
        scan(false);
        var device = mDevice;
        mDevice = null;
        mPercent = null;
        if (device != null) {
            BluetoothLowEnergy.unpairDevice(device);
        }
    }

    function scan(on as Lang.Boolean) as Void {
        BluetoothLowEnergy.setScanState(
            on ? BluetoothLowEnergy.SCAN_STATE_SCANNING : BluetoothLowEnergy.SCAN_STATE_OFF);
    }

    // --- BLE události --------------------------------------------------------

    function onScanResults(results as BluetoothLowEnergy.Iterator) as Void {
        if (mDevice != null) {
            return;
        }
        for (var result = results.next(); result != null; result = results.next()) {
            if (!(result instanceof BluetoothLowEnergy.ScanResult)) {
                continue;
            }
            var name = result.getDeviceName();
            if (name == null || name.toUpper().find(mName) == null) {
                continue;
            }
            // Během spojení už skenovat nemusíme, jen by to jedlo baterii.
            scan(false);
            mDevice = BluetoothLowEnergy.pairDevice(result);
            return;
        }
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device,
                                     state as BluetoothLowEnergy.ConnectionState) as Void {
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            mDevice = device;
            requestBattery();
            subscribe();
            return;
        }
        mDevice = null;
        mPercent = null;
        mReadAt = null;
        scan(true);
    }

    function onCharacteristicRead(characteristic as BluetoothLowEnergy.Characteristic,
                                  status as BluetoothLowEnergy.Status,
                                  value as Lang.ByteArray) as Void {
        if (status == BluetoothLowEnergy.STATUS_SUCCESS) {
            store(characteristic, value);
        }
    }

    function onCharacteristicChanged(characteristic as BluetoothLowEnergy.Characteristic,
                                     value as Lang.ByteArray) as Void {
        store(characteristic, value);
    }

    function store(characteristic as BluetoothLowEnergy.Characteristic,
                   value as Lang.ByteArray) as Void {
        if (!characteristic.getUuid().equals(BATTERY_LEVEL) || value.size() == 0) {
            return;
        }
        var percent = value[0] & 0xFF;
        if (percent > 100) {
            return;
        }
        mPercent = percent;
        mReadAt = System.getTimer();
    }

    // --- čtení ---------------------------------------------------------------

    function level() as BluetoothLowEnergy.Characteristic or Null {
        var device = mDevice;
        if (device == null) {
            return null;
        }
        var service = device.getService(BATTERY_SERVICE);
        return service == null ? null : service.getCharacteristic(BATTERY_LEVEL);
    }

    function requestBattery() as Void {
        var characteristic = level();
        if (characteristic != null) {
            characteristic.requestRead();
        }
    }

    //! Kolo hodnotu posílá samo jen když si o to řekneme zápisem do CCCD.
    function subscribe() as Void {
        var characteristic = level();
        if (characteristic == null) {
            return;
        }
        var cccd = characteristic.getDescriptor(BluetoothLowEnergy.cccdUuid());
        if (cccd != null) {
            cccd.requestWrite([0x01, 0x00]b);
        }
    }

    //! Volá se z tiku obrazovky; sama od sebe se baterie ozvat nemusí.
    function poll() as Void {
        if (mDevice == null) {
            return;
        }
        var last = mReadAt;
        if (last == null || System.getTimer() - last >= READ_INTERVAL_MS) {
            requestBattery();
        }
    }

    function batteryPercent() as Lang.Number or Null {
        return mDevice == null ? null : mPercent;
    }
}
