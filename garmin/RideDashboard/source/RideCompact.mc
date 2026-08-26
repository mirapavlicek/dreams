using Toybox.Graphics;
using Toybox.Lang;

//! Palubovka pro malý rámeček: mřížka metrik místo přístrojového štítu.
//!
//! Datové pole nedostane vždycky celou obrazovku. Když si ho jezdec dá na
//! datovou obrazovku vedle nativní mapy nebo Bosch polí, zbude na něj třeba
//! polovina výšky - a návrh počítaný na celý displej by se do ní jen svisle
//! zmáčkl. Tady se místo toho vybere tolik údajů, kolik se do rámečku vejde
//! čitelně, a rozloží se do dvou sloupců.
module RideCompact {

    //! Vejde se do rámečku celá palubovka, nebo je potřeba mřížka?
    //!
    //! Rozhoduje poměr stran proti návrhovému plátnu. Když je rámeček výrazně
    //! plošší, je to podíl na datové obrazovce, ne celý displej.
    function needed(dc) as Lang.Boolean {
        var canvas = RideLayout.section("canvas");
        var designed = (canvas["height"] as Lang.Number).toFloat() /
            (canvas["width"] as Lang.Number).toFloat();
        var actual = dc.getHeight().toFloat() / dc.getWidth().toFloat();
        return actual < designed * 0.75;
    }

    function draw(dc) as Void {
        RideLayout.prepare(dc);

        dc.setColor(RideLayout.color("background"), RideLayout.color("background"));
        dc.clear();

        var cells = metrics();
        var labelFont = Graphics.FONT_XTINY;
        var labelHeight = dc.getFontHeight(labelFont);
        var width = dc.getWidth();
        var height = dc.getHeight();
        var padding = labelHeight / 3;

        // Kolik řádků se vejde: na řádek je potřeba popiska, hodnota a mezera.
        var rowHeight = labelHeight * 2.6;
        var rows = ((height - padding * 2) / rowHeight).toNumber();
        if (rows < 1) {
            rows = 1;
        }
        var maximum = rows * 2;
        if (maximum > cells.size()) {
            maximum = cells.size();
        }
        rows = (maximum + 1) / 2;

        var columnWidth = width / 2;
        var top = (height - rows * rowHeight) / 2;

        for (var i = 0; i < maximum; i += 1) {
            var cell = cells[i] as Lang.Array;
            var column = i % 2;
            var row = i / 2;
            // Poslední osamocený údaj dostane celou šířku.
            var cx = maximum - i == 1 && column == 0
                ? width / 2
                : columnWidth * column + columnWidth / 2;
            var y = top + row * rowHeight;

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + labelHeight / 2,
                RideLayout.shrink(dc, RideLayout.textFonts(), labelFont, cell[0], columnWidth - 6),
                cell[0], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var value = cell[1] as Lang.String;
            var valueFont = RideLayout.shrink(dc, RideLayout.numberFonts(),
                Graphics.FONT_NUMBER_MEDIUM, value, columnWidth - 6);
            if (dc.getFontHeight(valueFont) > rowHeight - labelHeight) {
                valueFont = Graphics.FONT_MEDIUM;
            }
            dc.setColor(RideLayout.color(cell[2]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y + labelHeight + dc.getFontHeight(valueFont) / 2, valueFont, value,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Údaje od nejdůležitějšího; useknou se podle toho, co se vejde.
    function metrics() as Lang.Array {
        var cells = [
            ["RYCHLOST", RideData.speed().format("%.1f"), "text"],
            ["KADENCE", RideData.cadence().toString(), RideChrome.cadenceColor(RideData.cadence())]
        ];
        if (!RideData.ebikeNative()) {
            cells.add(["DOJEZD", RideData.assistRangeKm().format("%.0f"), "ok"]);
            cells.add(["BATERIE", RideData.assistBatteryPercent().toString() + " %", "ok"]);
        }
        cells.add(["NAJETO", RideData.distanceKm().format("%.1f"), "accent"]);
        var remaining = RideData.distanceToDestinationKm();
        cells.add(["DO CÍLE", remaining == null ? "--" : remaining.format("%.1f"), "accent"]);
        cells.add(["NASTOUPÁNO", RideData.ascent().toString(), "warn"]);
        cells.add(["SESTOUPÁNO", RideData.descent().toString(), "cold"]);
        return cells;
    }
}
