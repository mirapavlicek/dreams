using Toybox.Graphics;
using Toybox.Lang;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

//! Hlavní obrazovka: prstenec = hustota pravděpodobnosti |psi|^2 přes verdikty,
//! střed = kolaps měřením, spodní část = neurčitost a počty.
class DashboardView extends WatchUi.View {

    hidden var mTimer;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        var minutes = 15;
        if (Toybox.Application has :Properties) {
            var configured = Toybox.Application.Properties.getValue("refreshMinutes");
            if (configured instanceof Lang.Number && configured > 0) {
                minutes = configured;
            }
        }
        mTimer = new Timer.Timer();
        mTimer.start(method(:onRefreshTick), minutes * 60 * 1000, true);
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
    }

    function onRefreshTick() {
        QMailModel.refresh();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var size = width < height ? width : height;

        dc.setColor(QMailModel.color("background"), QMailModel.color("background"));
        dc.clear();

        drawRing(dc, width / 2, height / 2, size);
        drawTitle(dc, width, height);
        drawVerdict(dc, width, height, size);
        drawUncertainty(dc, width, height, size);
        drawFooter(dc, width, height);
    }

    //! Prstenec ze tří oblouků. Délka oblouku je přímo |psi|^2 daného verdiktu,
    //! takže obvod hodinek je celý pravděpodobnostní prostor.
    hidden function drawRing(dc, cx, cy, size) {
        var radius = (size * QMailModel.ring("radiusPct")).toNumber();
        var penWidth = (size * QMailModel.ring("widthPct")).toNumber();
        if (penWidth < 1) {
            penWidth = 1;
        }
        var gap = QMailModel.ring("gapDeg");
        var start = QMailModel.ring("startDeg");

        dc.setPenWidth(penWidth);
        dc.setColor(QMailModel.color("track"), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);

        var probabilities = QMailModel.probabilities();
        var names = ["ham", "spam", "phishing"];
        var available = 360.0 - gap * probabilities.size();
        var cursor = start;

        for (var i = 0; i < probabilities.size(); i += 1) {
            var sweep = probabilities[i] * available;
            if (sweep > 0.5) {
                dc.setColor(QMailModel.color(names[i]), Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, cursor, cursor - sweep);
            }
            cursor -= sweep + gap;
        }
    }

    hidden function drawTitle(dc, width, height) {
        var y = height * QMailModel.layout("titlePct");
        dc.setColor(QMailModel.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y, Graphics.FONT_XTINY, label(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function label() {
        return QMailModel.isDemo() ? "qmail · demo" : "qmail";
    }

    hidden function drawVerdict(dc, width, height, size) {
        var verdictColor = QMailModel.color(QMailModel.verdictColorName());

        dc.setColor(verdictColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * QMailModel.layout("verdictPct"), Graphics.FONT_LARGE,
            QMailModel.verdictLabel(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var percent = (QMailModel.confidence() * 100.0 + 0.5).toNumber();
        dc.setColor(QMailModel.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * QMailModel.layout("confidencePct"), Graphics.FONT_NUMBER_MEDIUM,
            percent.toString() + "%", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Entropie rozdělení: čím delší proužek, tím je vlnová funkce rozmazanější
    //! přes víc verdiktů a tím spíš patří e-mail k ruční kontrole.
    hidden function drawUncertainty(dc, width, height, size) {
        dc.setColor(QMailModel.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * QMailModel.layout("uncertaintyLabelPct"), Graphics.FONT_XTINY,
            "uncertainty " + formatRatio(QMailModel.uncertainty()),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var barWidth = size * QMailModel.layout("uncertaintyBarWidthPct");
        var barHeight = size * QMailModel.layout("uncertaintyBarHeightPct");
        if (barHeight < 2) {
            barHeight = 2;
        }
        var x = (width - barWidth) / 2;
        var y = height * QMailModel.layout("uncertaintyBarPct");

        dc.setColor(QMailModel.color("track"), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, barWidth, barHeight);

        var filled = barWidth * clamp(QMailModel.uncertainty(), 0.0, 1.0);
        if (filled > 0) {
            dc.setColor(QMailModel.color("accent"), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, y, filled, barHeight);
        }
    }

    hidden function drawFooter(dc, width, height) {
        var text = QMailModel.needsReview().toString() + "/" +
            QMailModel.scanned().toString() + " review";
        dc.setColor(QMailModel.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, height * QMailModel.layout("footerPct"), Graphics.FONT_XTINY, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function formatRatio(value) {
        return value.format("%.2f");
    }

    hidden function clamp(value, low, high) {
        if (value < low) {
            return low;
        }
        if (value > high) {
            return high;
        }
        return value;
    }
}

//! Stisk prostředního tlačítka / klepnutí vynutí nové měření.
class DashboardDelegate extends WatchUi.BehaviorDelegate {

    hidden var mView;

    function initialize(view) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    function onSelect() {
        QMailModel.refresh();
        WatchUi.requestUpdate();
        return true;
    }

    function onTap(event) {
        return onSelect();
    }
}
