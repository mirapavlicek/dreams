using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Timer;
using Toybox.WatchUi;

//! Konzole elektrokola.
//!
//! Palubovku na koukání dělají datová pole uvnitř nativní aktivity - tam teče
//! GPS i data o jízdě a vedle nich může svítit nativní mapa. Aplikace proto
//! nemá cenu jako druhá palubovka; má cenu jako to, co datové pole neumí:
//! **ovládat kolo a vidět, co o sobě hlásí.** Datové pole nedostává vstup,
//! takže stupeň asistence z něj přepnout nejde.
//!
//! Rozvržení se nebere z layout.json, ale počítá se z výšky písma - obrazovka
//! je prostý seznam a nemá smysl kvůli ní držet druhé návrhové plátno.
class RideBikeView extends WatchUi.View {

    hidden var mTimer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        mTimer = new Timer.Timer();
        mTimer.start(method(:onTick), 1000, true);
    }

    function onHide() {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
    }

    function onTick() as Void {
        try {
            RideData.poll();
        } catch (exception) {
            RideTrouble.note("čtení senzorů", exception);
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        if (RideTrouble.caught()) {
            RideTrouble.draw(dc);
            return;
        }
        try {
            RideLayout.prepare(dc);
            draw(dc);
        } catch (exception) {
            RideTrouble.note("konzole kola", exception);
            RideTrouble.draw(dc);
        }
    }

    function draw(dc) as Void {
        dc.setColor(RideLayout.color("background"), RideLayout.color("background"));
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var labelFont = Graphics.FONT_XTINY;
        var labelHeight = dc.getFontHeight(labelFont);
        var margin = labelHeight / 2;
        var y = margin;

        y = drawHeader(dc, width, y, labelFont, labelHeight);
        y = drawAssist(dc, width, y, height);
        y = drawBattery(dc, width, y, labelFont, labelHeight);
        drawDetails(dc, width, y, height - margin, labelHeight);
    }

    //! Hlavička: název a stav spojení s kolem.
    function drawHeader(dc, width, y, font, labelHeight) as Lang.Float {
        var bike = RideData.lev();
        var state = bike == null ? "kolo se neozývá" : "spojeno";
        var color = bike == null ? "textDim" : "ok";

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.s(6), y, font, "ELEKTROKOLO", Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(RideLayout.color(color), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width - RideLayout.s(6), y, font, state, Graphics.TEXT_JUSTIFY_RIGHT);
        return y + labelHeight * 1.2;
    }

    //! Stupeň asistence - to hlavní, protože je to jediné, co jde z aplikace
    //! měnit. Dokud kolo změnu nepotvrdí, ukazuje se se šipkou.
    function drawAssist(dc, width, y, height) as Lang.Float {
        var connected = RideData.lev() != null;
        var mode = RideData.assistModeLabel();
        if (mode == null) {
            mode = connected ? "ASIST ?" : "ČEKÁM NA KOLO";
        }
        var room = height * 0.28;
        var font = RideLayout.fitBox(dc, RideLayout.numberFonts(), mode, width - RideLayout.s(12),
            room);
        var textHeight = dc.getFontHeight(font);

        var color = "accent";
        if (!connected) {
            color = "textDim";
        } else if (RideData.pendingAssist() != null) {
            color = "warn";
        }
        dc.setColor(RideLayout.color(color), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y + textHeight / 2, font, mode,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        return y + textHeight;
    }

    //! Baterie procenty i proužkem, pod ní dojezd.
    function drawBattery(dc, width, y, font, labelHeight) as Lang.Float {
        var percent = RideData.assistBatteryPercent();
        var color = percent > 30 ? "ok" : "danger";
        var value = percent.toString() + " %   " + RideData.assistRangeKm().format("%.0f") + " km";
        var valueFont = RideLayout.fitBox(dc, RideLayout.numberFonts(), value,
            width - RideLayout.s(12), labelHeight * 2.4);
        var valueHeight = dc.getFontHeight(valueFont);

        dc.setColor(RideLayout.color(color), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y + valueHeight / 2, valueFont, value,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        y += valueHeight;

        var barHeight = labelHeight / 3;
        var barWidth = width - RideLayout.s(24);
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(RideLayout.s(12), y, barWidth, barHeight);
        dc.setColor(RideLayout.color(color), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(RideLayout.s(12), y, barWidth * RideChrome.clamp(percent / 100.0),
            barHeight);

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y + barHeight + labelHeight / 2, font, RideData.assistNote(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        return y + barHeight + labelHeight * 1.4;
    }

    //! Co kolo o sobě hlásí. Řádky se useknou, jakmile dojde místo.
    function drawDetails(dc, width, y, bottom, labelHeight) as Void {
        var rows = details();
        var font = Graphics.FONT_XTINY;

        // Řádky se rozprostřou po zbylé výšce, ať obrazovka nekončí půlkou
        // prázdna. Když je místa málo, sesypou se na výšku písma.
        var step = (bottom - y) / rows.size();
        if (step < labelHeight) {
            step = labelHeight;
        }

        for (var i = 0; i < rows.size(); i += 1) {
            if (y + labelHeight > bottom) {
                return;
            }
            var row = rows[i] as Lang.Array;
            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(RideLayout.s(6), y, font, row[0], Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(width - RideLayout.s(6), y, font, row[1], Graphics.TEXT_JUSTIFY_RIGHT);
            y += step;
        }
    }

    function details() as Lang.Array {
        var bike = RideData.lev();
        var consumption = bike == null ? null : bike.consumptionWhPerKm();
        var charged = bike == null ? null : bike.distanceOnChargeKm();
        var modes = bike == null ? null : bike.totalAssistModes();

        return [
            ["spotřeba", consumption == null ? "--" : consumption.format("%.1f") + " Wh/km"],
            ["od nabití", charged == null ? "--" : charged.format("%.1f") + " km"],
            ["stupňů asistence", modes == null ? "--" : modes.toString()],
            ["výrobce", RideBike.manufacturer()],
            ["ANT+ ID", RideData.mLevDeviceNumber == 0
                ? "hledá první kolo" : RideData.mLevDeviceNumber.toString()],
            ["ovládání", RideData.mControlLev ? "nahoru/dolů mění asistenci" : "vypnuté"]
        ];
    }
}

//! Jméno výrobce podle číselníku ze společné stránky 80 profilu LEV.
module RideBike {

    function manufacturer() as Lang.String {
        var bike = RideData.lev();
        if (bike == null || bike.manufacturer() == null) {
            return "--";
        }
        var id = bike.manufacturer();
        if (id == 63) { return "Specialized"; }
        if (id == 108) { return "Giant"; }
        if (id == 141) { return "TQ"; }
        if (id == 299) { return "Mahle"; }
        if (id == 304) { return "Yamaha"; }
        if (id == 318) { return "Fazua"; }
        return id.toString();
    }
}

class RideBikeDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() {
        RideMenu.open();
        return true;
    }

    function onNextPage() {
        return step(1);
    }

    function onPreviousPage() {
        return step(-1);
    }

    //! Asistence pod tlačítky nahoru a dolů. Když ovládání není zapnuté nebo
    //! kolo nemluví, událost se nezpracuje a přístroj si s tlačítkem naloží
    //! po svém - to je lepší, než ho tiše spolknout.
    function step(delta as Lang.Number) as Lang.Boolean {
        if (!RideData.canControlAssist()) {
            return false;
        }
        RideData.stepAssist(delta);
        WatchUi.requestUpdate();
        return true;
    }
}
