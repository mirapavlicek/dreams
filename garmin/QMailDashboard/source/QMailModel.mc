using Toybox.Application;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.PersistedContent;
using Toybox.WatchUi;

//! Držák dat dashboardu. Když je v nastavení vyplněná adresa qmail endpointu,
//! stáhne z ní aktuální rozdělení |psi|^2; jinak zůstane u demo dat, aby šel
//! dashboard ukázat i bez serveru (typicky v simulátoru).
(:glance)
module QMailModel {

    var mTheme = null;
    var mData = null;
    var mIsDemo = true;
    var mPending = false;

    //! Načte téma i data. Volá se opakovaně, druhé a další volání nic nedělá.
    function initialize() {
        if (mTheme == null) {
            mTheme = Application.loadResource(Rez.JsonData.Theme);
        }
        if (mData == null) {
            mData = demoData();
        }
        refresh();
    }

    //! Zahodí stažená data a načte je znovu (po změně nastavení).
    function reload() {
        mData = demoData();
        mIsDemo = true;
        refresh();
    }

    function theme() as Lang.Dictionary {
        if (mTheme == null) {
            mTheme = Application.loadResource(Rez.JsonData.Theme);
        }
        return mTheme as Lang.Dictionary;
    }

    function section(name) as Lang.Dictionary {
        return theme()[name] as Lang.Dictionary;
    }

    function color(name) {
        return section("colors")[name];
    }

    function ring(name) {
        return (section("ring")[name] as Lang.Number).toFloat();
    }

    function layout(name) {
        return (section("layout")[name] as Lang.Number).toFloat();
    }

    function data() as Lang.Dictionary {
        if (mData == null) {
            mData = demoData();
        }
        return mData as Lang.Dictionary;
    }

    function isDemo() {
        return mIsDemo;
    }

    //! Pravděpodobnosti v pořadí [ham, spam, phishing]; vždy sečtené na 1.
    function probabilities() as Lang.Array<Lang.Float> {
        var p = data()["probabilities"] as Lang.Dictionary;
        var values = [toFloat(p["ham"], 0.0), toFloat(p["spam"], 0.0), toFloat(p["phishing"], 0.0)];
        var sum = values[0] + values[1] + values[2];
        if (sum <= 0.0) {
            return [1.0, 0.0, 0.0];
        }
        return [values[0] / sum, values[1] / sum, values[2] / sum];
    }

    //! Index kolapsu: 0 = ham, 1 = spam, 2 = phishing.
    function verdictIndex() {
        var p = probabilities();
        var best = 0;
        for (var i = 1; i < p.size(); i += 1) {
            if (p[i] > p[best]) {
                best = i;
            }
        }
        return best;
    }

    function verdictLabel() {
        var labels = ["LEGIT", "SPAM", "PHISH"];
        return labels[verdictIndex()];
    }

    function verdictColorName() {
        var names = ["ham", "spam", "phishing"];
        return names[verdictIndex()];
    }

    function confidence() {
        return probabilities()[verdictIndex()];
    }

    function uncertainty() {
        return toFloat(data()["uncertainty"], 0.0);
    }

    function needsReview() {
        return toNumber(data()["needs_review"], 0);
    }

    function scanned() {
        return toNumber(data()["scanned"], 0);
    }

    function toFloat(value, fallback) {
        if (value instanceof Lang.Number || value instanceof Lang.Float ||
            value instanceof Lang.Long || value instanceof Lang.Double) {
            return value.toFloat();
        }
        return fallback;
    }

    function toNumber(value, fallback) {
        if (value instanceof Lang.Number || value instanceof Lang.Float ||
            value instanceof Lang.Long || value instanceof Lang.Double) {
            return value.toNumber();
        }
        return fallback;
    }

    //! Rozbor phishingového vzorku z examples/phishing.eml – slouží jako
    //! výchozí obsah dashboardu, dokud nedorazí data ze serveru.
    function demoData() {
        return {
            "probabilities" => { "ham" => 0.011, "spam" => 0.027, "phishing" => 0.963 },
            "uncertainty" => 0.165,
            "needs_review" => 3,
            "scanned" => 128
        };
    }

    function apiUrl() {
        if (!(Application has :Properties)) {
            return null;
        }
        var url = Application.Properties.getValue("apiUrl");
        if (url == null || !(url instanceof Lang.String) || url.length() == 0) {
            return null;
        }
        return url;
    }

    function refresh() {
        var url = apiUrl();
        if (url == null || mPending || !(Communications has :makeWebRequest)) {
            return;
        }
        mPending = true;
        new QMailFetcher().start(url);
    }

    function onResponse(responseCode, response) {
        mPending = false;
        if (responseCode == 200 && response instanceof Lang.Dictionary &&
            response["probabilities"] instanceof Lang.Dictionary) {
            mData = response;
            mIsDemo = false;
            WatchUi.requestUpdate();
        }
    }

    function stopRefresh() {
        mPending = false;
    }
}

//! Modul si nemůže vzít referenci na vlastní funkci (`method(:x)` existuje jen
//! nad instancí), takže odpověď z webu odchytí tahle drobná třída a předá ji
//! zpátky do QMailModel.
(:glance)
class QMailFetcher {

    function initialize() {
    }

    function start(url) as Void {
        Communications.makeWebRequest(
            url,
            null,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onReceive)
        );
    }

    function onReceive(
        responseCode as Lang.Number,
        data as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator
    ) as Void {
        QMailModel.onResponse(responseCode, data);
    }
}
