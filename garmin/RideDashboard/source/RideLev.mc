using Toybox.Ant;
using Toybox.Lang;
using Toybox.System;

//! Elektrokolo přes ANT+ profil LEV (Light Electric Vehicle, device type 20).
//!
//! Edge sám dojezd i stav baterie kola zobrazuje, jenže Connect IQ na to nemá
//! hotovou třídu jako na pulsy nebo výkon - v Toybox.AntPlus profil LEV chybí.
//! Otevřeme si tedy vlastní generický kanál a bajty datových stránek
//! dekódujeme ručně podle profilu. Kanál je jen poslouchající (RX_ONLY), takže
//! kolu nic neposíláme a nemluvíme mu do toho, co si s ním řeší přístroj.
//!
//! Kolo musí LEV umět - Specialized, Fazua, Giant nebo Mahle ano, Bosch a
//! Shimano po svém, tam zůstane odhad v RideData.
class RideLev extends Ant.GenericChannel {

    //: Device type 20 (0x14) na frekvenci 57 a periodě 8192 = 4 Hz.
    const DEVICE_TYPE = 20;
    const PERIOD = 8192;
    const FREQUENCY = 57;

    //: Po takhle dlouhém tichu považujeme hodnoty za neplatné.
    const STALE_MS = 6000;

    var mAssign as Ant.ChannelAssignment or Null = null;
    var mSearching as Lang.Boolean = true;
    var mLastMessage as Lang.Number or Null = null;

    var mSoc as Lang.Number or Null = null;
    var mBatteryWarning as Lang.Boolean = false;
    var mRangeKm as Lang.Float or Null = null;
    var mConsumption as Lang.Float or Null = null;
    var mChargeDistanceKm as Lang.Float or Null = null;
    var mAssistLevel as Lang.Number or Null = null;
    var mAssistPercent as Lang.Number or Null = null;
    var mSpeedKmh as Lang.Float or Null = null;

    //! @param deviceNumber ANT+ ID kola, nula hledá první, které se ozve.
    function initialize(deviceNumber as Lang.Number) {
        mAssign = new Ant.ChannelAssignment(Ant.CHANNEL_TYPE_RX_ONLY, Ant.NETWORK_PLUS);
        GenericChannel.initialize(method(:onMessage), mAssign);
        GenericChannel.setDeviceConfig(new Ant.DeviceConfig({
            :deviceNumber => deviceNumber,
            :deviceType => DEVICE_TYPE,
            :transmissionType => 0,
            :messagePeriod => PERIOD,
            :radioFrequency => FREQUENCY,
            :searchTimeoutLowPriority => 12,
            :searchThreshold => 0
        }));
    }

    function open() as Lang.Boolean {
        mSearching = true;
        return GenericChannel.open();
    }

    function shutdown() as Void {
        GenericChannel.close();
        GenericChannel.release();
    }

    // --- příjem --------------------------------------------------------------

    function onMessage(message as Ant.Message) as Void {
        var payload = message.getPayload();

        if (Ant.MSG_ID_BROADCAST_DATA == message.messageId) {
            mSearching = false;
            mLastMessage = System.getTimer();
            parse(payload);
            return;
        }

        if (Ant.MSG_ID_CHANNEL_RESPONSE_EVENT == message.messageId &&
            Ant.MSG_ID_RF_EVENT == (payload[0] & 0xFF)) {
            var code = payload[1] & 0xFF;
            if (Ant.MSG_CODE_EVENT_CHANNEL_CLOSED == code) {
                // Vypršelo hledání nebo kolo usnulo; zkusíme to znovu.
                open();
            } else if (Ant.MSG_CODE_EVENT_RX_FAIL_GO_TO_SEARCH == code) {
                mSearching = true;
            }
        }
    }

    //! Rozdělení bajtů podle profilu LEV. Stránky 1-3 chodí každou vteřinu,
    //! stránka 4 a 5 jen občas nebo na vyžádání.
    function parse(payload as Lang.Array<Lang.Number>) as Void {
        var page = payload[0] & 0xFF;

        if (page == 1) {
            mAssistLevel = (payload[2] >> 3) & 0x07;
            mSpeedKmh = speedFrom(payload);

        } else if (page == 2) {
            // Dojezd: 12 bitů po kilometru, nula znamená "kolo neví".
            var range = (payload[4] & 0xFF) | ((payload[5] & 0x0F) << 8);
            mRangeKm = range == 0 ? null : range.toFloat();
            mSpeedKmh = speedFrom(payload);

        } else if (page == 3) {
            // Nejvyšší bit je varování o prázdné baterii, zbytek procenta.
            var soc = payload[1] & 0x7F;
            mSoc = soc > 100 ? null : soc;
            mBatteryWarning = ((payload[1] >> 7) & 0x01) == 1;
            mAssistLevel = (payload[2] >> 3) & 0x07;
            var assist = payload[5] & 0xFF;
            mAssistPercent = assist == 0xFF ? null : assist;
            mSpeedKmh = speedFrom(payload);

        } else if (page == 4) {
            // Spotřeba má nižší bajt na čtyřce a horní půlbajt na trojce.
            var consumption = (payload[4] & 0xFF) | (((payload[3] >> 4) & 0x0F) << 8);
            mConsumption = consumption == 0 ? null : consumption / 10.0;
            var charged = (payload[6] & 0xFF) | ((payload[7] & 0xFF) << 8);
            mChargeDistanceKm = charged == 0 ? null : charged / 10.0;

        } else if (page == 34) {
            // Náhrada za stránku 2: místo dojezdu posílá spotřebu ve Wh/km.
            var alternate = (payload[4] & 0xFF) | ((payload[5] & 0x0F) << 8);
            mConsumption = alternate == 0 ? null : alternate / 10.0;
            mSpeedKmh = speedFrom(payload);
        }
    }

    //! Rychlost kola sedí na stejném místě ve stránkách 1, 2, 3 i 34.
    function speedFrom(payload as Lang.Array<Lang.Number>) as Lang.Float {
        return ((payload[6] & 0xFF) | ((payload[7] & 0x0F) << 8)) / 10.0;
    }

    // --- hodnoty pro dashboard ----------------------------------------------

    //! Mluví s námi kolo? Po pár vteřinách ticha už hodnotám nevěříme.
    function connected() as Lang.Boolean {
        var last = mLastMessage;
        if (last == null) {
            return false;
        }
        var age = System.getTimer() - last;
        // Čítač přeteče zhruba po 24 dnech; záporný rozdíl bereme jako čerstvý.
        return age < 0 || age < STALE_MS;
    }

    function searching() as Lang.Boolean {
        return mSearching;
    }

    //! Dojezd v kilometrech tak, jak ho spočítalo samo kolo.
    function rangeKm() as Lang.Float or Null {
        return connected() ? mRangeKm : null;
    }

    //! Stav baterie v procentech.
    function batteryPercent() as Lang.Number or Null {
        return connected() ? mSoc : null;
    }

    function batteryWarning() as Lang.Boolean {
        return connected() && mBatteryWarning;
    }

    //! Okamžitá spotřeba ve watthodinách na kilometr.
    function consumptionWhPerKm() as Lang.Float or Null {
        return connected() ? mConsumption : null;
    }

    //! Kolik kilometrů kolo ujelo od posledního nabití.
    function distanceOnChargeKm() as Lang.Float or Null {
        return connected() ? mChargeDistanceKm : null;
    }

    //! Stupeň asistence 0-7; nula je vypnutá pomoc.
    function assistLevel() as Lang.Number or Null {
        return connected() ? mAssistLevel : null;
    }

    function assistPercent() as Lang.Number or Null {
        return connected() ? mAssistPercent : null;
    }

    function speedKmh() as Lang.Float or Null {
        return connected() ? mSpeedKmh : null;
    }
}
