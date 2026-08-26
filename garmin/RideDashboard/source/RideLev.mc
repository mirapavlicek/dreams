using Toybox.Ant;
using Toybox.Application;
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

    //: Ovládací stránka, kterou displej posílá kolu (profil LEV, kap. 5.10).
    //: Kolo ji musí umět - podle profilu je povinná pro každé LEV.
    const PAGE_DISPLAY = 16;

    //: Výrobce displeje. Nejsme registrovaní u ANT+, takže vývojářská 255
    //: jako ve FIT číselníku.
    const DISPLAY_MANUFACTURER = 255;

    //: Obvod kola nenastavujeme, profil na to má 0xFFF.
    const WHEEL_UNSET = 0xFFF;

    //: Po takhle dlouhém tichu považujeme hodnoty za neplatné.
    const STALE_MS = 6000;

    //: Výrobci ze společné stránky 80 (číselník je stejný jako v FIT). Stupně
    //: asistence 0-7 mají u každého jiná jména a na displeji kola svítí ta,
    //: ne čísla.
    const MANUFACTURER_SPECIALIZED = 63;
    const MANUFACTURER_GIANT = 108;
    const MANUFACTURER_TQ = 141;
    const MANUFACTURER_MAHLE = 299;
    const MANUFACTURER_YAMAHA = 304;
    const MANUFACTURER_FAZUA = 318;

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
    var mManufacturer as Lang.Number or Null = null;
    var mTotalAssistModes as Lang.Number or Null = null;

    //: Stav světel, blinkrů a převodů tak, jak ho kolo hlásí ve stránce 1.
    //: Do ovládací stránky se musí vrátit beze změny - kdybychom tam poslali
    //: nuly, řekli bychom kolu zároveň "zhasni a zruš blinkr".
    var mSystemState as Lang.Number = 0;
    var mGearState as Lang.Number = 0;
    var mRegenLevel as Lang.Number = 0;

    //: Poslední odeslaný požadavek, dokud ho kolo nepotvrdí změnou stránky 1.
    var mRequestedAssist as Lang.Number or Null = null;

    //! @param deviceNumber ANT+ ID kola, nula hledá první, které se ozve.
    function initialize(deviceNumber as Lang.Number) {
        // Profil pro displej předepisuje obousměrný slave kanál ("Bidirectional
        // communication is required", tabulka 4-1). Jen poslouchající kanál by
        // sice na čtení stačil, ale ovládací stránku by nešlo odeslat.
        mAssign = new Ant.ChannelAssignment(Ant.CHANNEL_TYPE_RX_NOT_TX, Ant.NETWORK_PLUS);
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
        try {
            handle(message);
        } catch (exception) {
            // Zprávy z kola jsou jediné, co v simulátoru nikdy neproteče.
            // Když se v nich něco nečekaného objeví, ať to shodí čtení dat,
            // ne celou palubovku.
            RideTrouble.note("data z kola (ANT+)", exception);
        }
    }

    function handle(message as Ant.Message) as Void {
        var payload = message.getPayload();

        if (Ant.MSG_ID_BROADCAST_DATA == message.messageId) {
            if (mSearching) {
                mSearching = false;
                rememberDeviceNumber();
            }
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
            setAssistLevel((payload[2] >> 3) & 0x07);
            mRegenLevel = payload[2] & 0x07;
            mSystemState = payload[3] & 0xFF;
            mGearState = payload[4] & 0xFF;
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
            setAssistLevel((payload[2] >> 3) & 0x07);
            mRegenLevel = payload[2] & 0x07;
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

        } else if (page == 5) {
            mTotalAssistModes = (payload[2] >> 3) & 0x07;

        } else if (page == 80) {
            // Společná stránka s výrobcem; podle něj pojmenujeme režimy.
            mManufacturer = (payload[4] & 0xFF) | ((payload[5] & 0xFF) << 8);
        }
    }

    //! Stupeň z kola. Když dorazil ten, o který jsme si řekli, požadavek
    //! splnil účel a zahodí se; do té doby ukazujeme dál kolem hlášenou
    //! skutečnost, ne naše přání.
    function setAssistLevel(level as Lang.Number) as Void {
        mAssistLevel = level;
        if (mRequestedAssist != null && mRequestedAssist == level) {
            mRequestedAssist = null;
        }
    }

    // --- ovládání ------------------------------------------------------------

    //! Požádá kolo o jiný stupeň asistence (datová stránka 16 profilu LEV).
    //!
    //! Stránka nenese jen asistenci - v bajtech 4 a 5 je "desired state" pro
    //! převody, světla, dálková a blinkry. Posílají se proto zpátky přesně tak,
    //! jak je kolo naposledy hlásilo ve stránce 1; jinak by změna stupně
    //! zároveň zhasla světla. Rekuperace se ze stejného důvodu opisuje.
    //!
    //! @return true, když se zprávu podařilo předat rádiu
    function requestAssist(level as Lang.Number) as Lang.Boolean {
        if (!connected() || level < 0 || level > 7) {
            return false;
        }

        var command = displayCommand();
        var payload = [
            PAGE_DISPLAY,
            WHEEL_UNSET & 0xFF,
            0xF0 | ((WHEEL_UNSET >> 8) & 0x0F),
            ((level & 0x07) << 3) | (mRegenLevel & 0x07),
            command & 0xFF,
            (command >> 8) & 0xFF,
            DISPLAY_MANUFACTURER & 0xFF,
            (DISPLAY_MANUFACTURER >> 8) & 0xFF
        ];

        var message = new Ant.Message();
        message.setPayload(payload);
        // Potvrzovanou zprávou, ať se pozná, že kolo stránku dostalo.
        var sent = GenericChannel.sendAcknowledge(message);
        if (sent) {
            mRequestedAssist = level;
        }
        return sent;
    }

    //! Bity převodů, světel a blinkrů pro ovládací stránku, poskládané ze
    //! stavu, který kolo hlásí. Rozložení bitů se mezi stránkou 1 a stránkou 16
    //! liší, proto se převádí a neopisuje.
    function displayCommand() as Lang.Number {
        var rearGear = (mGearState >> 2) & 0x0F;
        var frontGear = mGearState & 0x03;
        var lights = mSystemState & 0x0F;
        return ((rearGear & 0x0F) << 6) | ((frontGear & 0x03) << 4) | lights;
    }

    //! Stupeň, na který čekáme, dokud ho kolo nepotvrdí.
    function requestedAssist() as Lang.Number or Null {
        return connected() ? mRequestedAssist : null;
    }

    //! Po spárování si ANT+ ID kola uložíme, aby se příště kanál nechytil
    //! cizího kola, které jede kolem.
    function rememberDeviceNumber() as Void {
        if (!(Application has :Properties)) {
            return;
        }
        var found = GenericChannel.getDeviceConfig().deviceNumber;
        if (found == null || found == 0) {
            return;
        }
        var stored = Application.Properties.getValue("levDeviceNumber");
        if (stored instanceof Lang.Number && stored == found) {
            return;
        }
        Application.Properties.setValue("levDeviceNumber", found);
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

    function manufacturer() as Lang.Number or Null {
        return connected() ? mManufacturer : null;
    }

    //! Jak se stupeň asistence jmenuje na displeji kola. Profil posílá jen
    //! číslo 0-7, jména jsou věc výrobce. Když značku neznáme nebo si nejsme
    //! jistí, který stupeň je který, vrátíme null a nahoře se ukáže číslo -
    //! vymýšlet si jméno je horší než ho neukázat.
    function assistModeName() as Lang.String or Null {
        var level = assistLevel();
        if (level == null) {
            return null;
        }
        if (level == 0) {
            return "VYPNUTO";
        }

        var known = expandedModeNames();
        if (known != null) {
            return level < known.size() ? known[level] : null;
        }

        // U ostatních značek známe jen pořadí režimů, ne jejich rozprostření
        // po sedmi stupních profilu. Pojmenujeme je proto jen tehdy, když kolo
        // hlásí přesně tolik stupňů, kolik jich značka má - pak je to jedna
        // ku jedné a není co odhadovat.
        var ordered = orderedModeNames();
        if (ordered == null || mTotalAssistModes == null ||
            mTotalAssistModes != ordered.size() || level > ordered.size()) {
            return null;
        }
        return ordered[level - 1];
    }

    //! Značky, u kterých je ověřené i rozprostření jmen po stupních 0-7.
    //! Kola s méně režimy stupně zdvojují, proto se jména opakují.
    function expandedModeNames() as Lang.Array<Lang.String> or Null {
        if (mManufacturer == MANUFACTURER_GIANT) {
            return ["VYPNUTO", "ECO", "BASIC", "ACTIVE", "AUTO", "SPORT", "POWER", "POWER"];
        }
        if (mManufacturer == MANUFACTURER_SPECIALIZED || mManufacturer == MANUFACTURER_MAHLE) {
            return ["VYPNUTO", "ECO", "ECO", "TRAIL", "TRAIL", "TURBO", "TURBO", "TURBO"];
        }
        if (mManufacturer == MANUFACTURER_YAMAHA) {
            return ["VYPNUTO", "ECO+", "ECO", "STD", "HIGH", "HIGH", "EXPW", "EXPW"];
        }
        return null;
    }

    //! Značky, kde známe režimy v pořadí od nejslabšího.
    function orderedModeNames() as Lang.Array<Lang.String> or Null {
        if (mManufacturer == MANUFACTURER_FAZUA) {
            return ["BREEZE", "RIVER", "ROCKET"];
        }
        if (mManufacturer == MANUFACTURER_TQ) {
            return ["ECO", "MID", "HIGH"];
        }
        return null;
    }

    //! Kolik stupňů asistence kolo hlásí (stránka 5).
    function totalAssistModes() as Lang.Number or Null {
        return connected() ? mTotalAssistModes : null;
    }
}
