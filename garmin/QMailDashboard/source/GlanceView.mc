using Toybox.Graphics;
using Toybox.WatchUi;

//! Glance: jeden řádek v seznamu aplikací – verdikt, jistota a mini pruh
//! s rozdělením |psi|^2.
(:glance)
class QMailGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.setColor(Graphics.COLOR_TRANSPARENT, QMailModel.color("background"));
        dc.clear();

        var percent = (QMailModel.confidence() * 100.0 + 0.5).toNumber();
        var text = "qmail · " + QMailModel.verdictLabel() + " " + percent.toString() + "%";

        dc.setColor(QMailModel.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, height / 2, Graphics.FONT_GLANCE, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        drawDistributionBar(dc, 0, height - 6, width, 4);
    }

    hidden function drawDistributionBar(dc, x, y, width, height) {
        var probabilities = QMailModel.probabilities();
        var names = ["ham", "spam", "phishing"];
        var cursor = x;

        dc.setColor(QMailModel.color("track"), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, width, height);

        for (var i = 0; i < probabilities.size(); i += 1) {
            var segment = width * probabilities[i];
            if (segment >= 1) {
                dc.setColor(QMailModel.color(names[i]), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cursor, y, segment, height);
            }
            cursor += segment;
        }
    }
}
