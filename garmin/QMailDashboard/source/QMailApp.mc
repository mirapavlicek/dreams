using Toybox.Application;
using Toybox.WatchUi;

//! Hodinková aplikace, která ukazuje stav poštovní schránky tak, jak ho počítá
//! knihovna qmail: jako hustotu pravděpodobnosti |psi|^2 přes verdikty
//! ham / spam / phishing, se zvýrazněným kolapsem a mírou neurčitosti.
class QMailApp extends Application.AppBase {

    hidden var mView;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
        QMailModel.initialize();
    }

    function onStop(state) {
        QMailModel.stopRefresh();
    }

    function getInitialView() {
        mView = new DashboardView();
        return [mView, new DashboardDelegate(mView)];
    }

    (:glance)
    function getGlanceView() {
        QMailModel.initialize();
        return [new QMailGlanceView()];
    }

    function onSettingsChanged() {
        QMailModel.reload();
        WatchUi.requestUpdate();
    }
}
