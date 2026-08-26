using Toybox.Activity;
using Toybox.ActivityRecording;
using Toybox.Lang;
using Toybox.Time;

//! Nahrávání jízdy.
//!
//! Bez tohohle je palubovka na Edge k ničemu, i když se tváří, že běží.
//! Samostatná Connect IQ aplikace totiž stojí **mimo nativní aktivitu**:
//! `Activity.getActivityInfo()` vrací prázdno (`dist=null`, `acc=null`), přístroj
//! nemá důvod zapínat GPS a mapa nemá polohu, na kterou by se vycentrovala.
//! Teprve založená a spuštěná relace udělá z aplikace skutečný cyklopočítač.
module RideRecord {

    var mSession = null;

    function available() as Lang.Boolean {
        return (Toybox has :ActivityRecording) as Lang.Boolean;
    }

    //! Relace se zakládá až při prvním spuštění, ne při startu aplikace -
    //! otevřít si palubovku ještě neznamená vyrazit na kolo.
    function session() {
        if (mSession == null && available()) {
            mSession = ActivityRecording.createSession({
                :name => "Ride Dashboard",
                :sport => Activity.SPORT_CYCLING,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
        }
        return mSession;
    }

    function recording() as Lang.Boolean {
        return mSession != null && mSession.isRecording();
    }

    //! Je co uložit? Po zastavení relace zůstává rozjetá, dokud se neuloží
    //! nebo nezahodí.
    function pending() as Lang.Boolean {
        return mSession != null;
    }

    //! Start/stop pod tlačítkem Start, jak je na cyklopočítači zvykem.
    function toggle() as Lang.Boolean {
        if (!available()) {
            return false;
        }
        try {
            var active = session();
            if (active == null) {
                return false;
            }
            if (active.isRecording()) {
                active.stop();
            } else {
                active.start();
            }
        } catch (exception) {
            RideTrouble.note("nahrávání jízdy", exception);
            return false;
        }
        return true;
    }

    function save() as Void {
        finish(true);
    }

    function discard() as Void {
        finish(false);
    }

    function finish(keep as Lang.Boolean) as Void {
        var active = mSession;
        if (active == null) {
            return;
        }
        try {
            if (active.isRecording()) {
                active.stop();
            }
            if (keep) {
                active.save();
            } else {
                active.discard();
            }
        } catch (exception) {
            RideTrouble.note("ukládání jízdy", exception);
        }
        mSession = null;
    }

    //! Předá stav kreslení, které je sdílené s datovým polem a o nahrávání
    //! nic neví.
    function publish() as Void {
        if (!pending()) {
            RideData.setRideState("START", false);
            return;
        }
        RideData.setRideState(elapsed(), recording());
    }

    //! Čas jízdy jako mm:ss, po hodině hh:mm:ss.
    function elapsed() as Lang.String {
        var info = RideData.info();
        if (info == null || !(info.timerTime instanceof Lang.Number)) {
            return "0:00";
        }
        var seconds = info.timerTime / 1000;
        var minutes = seconds / 60;
        if (minutes < 60) {
            return minutes.format("%d") + ":" + (seconds % 60).format("%02d");
        }
        return (minutes / 60).format("%d") + ":" + (minutes % 60).format("%02d") + ":" +
            (seconds % 60).format("%02d");
    }
}
