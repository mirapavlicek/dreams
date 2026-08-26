using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Weather;

//! Kreslení palubovky. Souřadnice jsou v pixelech návrhu 480x800 a RideLayout
//! je přepočítá na skutečný displej.
//!
//! Stejné vykreslení používají dvě obrazovky: RideView s drobečkovou stopou a
//! RideMapView s mapou z paměti přístroje. Liší se jen tím, co je v prostředním
//! okně - proto `mapBehind`.
module RideChrome {

    //! @param mapBehind true, když pod palubovkou kreslí mapu systém; pak se
    //!        plátno nemaže celé, ale jen okolo mapového okna.
    function draw(dc, mapBehind as Lang.Boolean) as Void {
        RideLayout.prepare(dc);
        fillBackground(dc, mapBehind);

        drawClock(dc);
        drawCadence(dc);
        drawSpeed(dc);
        drawSpeedStats(dc);

        var dividerY = RideLayout.y(RideLayout.number("divider", "y"));
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        var margin = RideLayout.number("divider", "margin");
        dc.drawLine(RideLayout.x(margin), dividerY,
            RideLayout.x(RideLayout.number("canvas", "width") - margin), dividerY);

        drawMiddle(dc, mapBehind);
        drawBottom(dc);
    }

    //! Mapa se vykresluje pod celou obrazovkou, takže v mapovém režimu smíme
    //! přebarvit jen pruhy kolem okna - jinak bychom kartografii zakryli.
    function fillBackground(dc, mapBehind as Lang.Boolean) as Void {
        dc.setColor(RideLayout.color("background"), RideLayout.color("background"));
        if (!mapBehind) {
            dc.clear();
            return;
        }

        var rect = RideLayout.mapRect() as Lang.Array;
        var left = rect[0] as Lang.Number;
        var top = rect[1] as Lang.Number;
        var right = rect[2] as Lang.Number;
        var bottom = rect[3] as Lang.Number;
        var width = dc.getWidth();
        var height = dc.getHeight();

        dc.fillRectangle(0, 0, width, top);
        dc.fillRectangle(0, bottom, width, height - bottom);
        dc.fillRectangle(0, top, left, bottom - top);
        dc.fillRectangle(right, top, width - right, bottom - top);
    }

    // --- kreslicí pomocníky -------------------------------------------------

    function panel(dc, x, y, width, height, radius) as Void {
        var px = RideLayout.x(x);
        var py = RideLayout.y(y);
        var pw = RideLayout.x(width);
        var ph = RideLayout.dy(height);
        var pr = RideLayout.s(radius);

        dc.setColor(RideLayout.color("panel"), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(px, py, pw, ph, pr);
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(px, py, pw, ph, pr);
    }

    function label(dc, x, y, text, size, colorName) as Void {
        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x), RideLayout.y(y), RideLayout.textFont(dc, size), text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Popiska na střed, která se vejde do `width` návrhových pixelů.
    //! Nejmenší Garmin font je pořád větší, než si návrh představuje, takže bez
    //! tohohle by si sousední sloupce lezly do textu.
    function labelIn(dc, cx, y, width, text, size, colorName) as Void {
        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(cx), RideLayout.y(y),
            RideLayout.fitFont(dc, text, RideLayout.x(width), size), text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Nejdelší z nabídnutých variant textu, která se vejde do `room` pixelů
    //! displeje, jako dvojice [font, text].
    //!
    //! Pod FONT_XTINY se zmenšit nedá, takže na úzkém sloupci se dlouhá popiska
    //! vejít nemůže ani teoreticky. Místo přetékání se proto sáhne po kratší
    //! variantě ("E-BIKE · ODHAD" -> "ODHAD"), a když ani ta nestačí, nekreslí
    //! se nic - rozmazaná změť písmen řekne míň než prázdné místo.
    function fitText(dc, choices as Lang.Array, room, size) as Lang.Array {
        for (var i = 0; i < choices.size(); i += 1) {
            var text = choices[i] as Lang.String;
            var font = RideLayout.fitFont(dc, text, room, size);
            if (dc.getTextWidthInPixels(text, font) <= room) {
                return [font, text];
            }
        }
        return [RideLayout.textFont(dc, size), ""];
    }

    //! Dvojice popisek stejné délky pro sousední sloupce.
    //!
    //! Kdyby se vybíraly zvlášť, na určité šířce by u jedné šipky slovo zbylo
    //! a u druhé ne - jedno je o písmeno kratší a zrovna se ještě vejde.
    //! @param variants dvojice od nejdelší, třeba [["NASTOUPÁNO", "SESTOUPÁNO"],
    //!        ["STOUPÁNÍ", "KLESÁNÍ"]]
    function fitPair(dc, variants as Lang.Array, room, size) as Lang.Array {
        for (var i = 0; i < variants.size(); i += 1) {
            var pair = variants[i] as Lang.Array;
            var first = RideLayout.fitFont(dc, pair[0], room, size);
            var second = RideLayout.fitFont(dc, pair[1], room, size);
            if (dc.getTextWidthInPixels(pair[0], first) <= room &&
                dc.getTextWidthInPixels(pair[1], second) <= room) {
                return pair;
            }
        }
        return ["", ""];
    }

    function number(dc, x, y, text, size, colorName) as Void {
        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x), RideLayout.y(y), RideLayout.numberFont(dc, size), text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function bar(dc, x, y, width, height, ratio, colorName) as Void {
        var filled = ratio;
        if (filled < 0.0) {
            filled = 0.0;
        }
        if (filled > 1.0) {
            filled = 1.0;
        }
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(RideLayout.x(x), RideLayout.y(y), RideLayout.x(width), RideLayout.dy(height));
        if (filled > 0.0) {
            dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(RideLayout.x(x), RideLayout.y(y), RideLayout.x(width * filled), RideLayout.dy(height));
        }
    }

    // --- horní lišta --------------------------------------------------------

    function drawClock(dc) as Void {
        var centerY = RideLayout.number("clock", "y") + RideLayout.number("clock", "height") / 2.0;

        number(dc, RideLayout.centerX(), centerY, RideData.clockString(),
            RideLayout.number("clock", "size"), "text");

        dc.setColor(RideData.hasFix() ? RideLayout.color("ok") : RideLayout.color("textDim"),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(14), RideLayout.y(centerY), RideLayout.textFont(dc, 13), "GPS",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(466), RideLayout.y(centerY), RideLayout.textFont(dc, 13),
            RideData.deviceBatteryPercent().toString() + "%",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- půlkruh kadence ----------------------------------------------------

    function cadenceColor(cadence) {
        if (cadence < 50) {
            return "textDim";
        }
        if (cadence <= 100) {
            return "ok";
        }
        if (cadence <= 150) {
            return "warn";
        }
        return "danger";
    }

    function drawCadence(dc) as Void {
        var cx = RideLayout.x(RideLayout.number("cadence", "cx"));
        var cy = RideLayout.y(RideLayout.number("cadence", "cy"));
        var radius = RideLayout.s(RideLayout.number("cadence", "radius"));
        var pen = RideLayout.s(RideLayout.number("cadence", "pen"));
        var maximum = RideLayout.number("cadence", "max");
        var cadence = RideData.cadence();

        dc.setPenWidth(pen.toNumber());
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        // Garmin měří úhly proti směru hodinových ručiček od tří hodin, takže
        // horní půlkruh je oblouk po směru od 180 do 0 stupňů.
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 180, 0);

        var ratio = cadence / maximum;
        if (ratio > 1.0) {
            ratio = 1.0;
        }
        if (ratio > 0.005) {
            dc.setColor(RideLayout.color(cadenceColor(cadence)), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 180, 180 - 180.0 * ratio);
        }

        var ticks = RideLayout.value("cadence", "ticks") as Lang.Array;
        dc.setPenWidth(2);
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < ticks.size(); i += 1) {
            var tick = (ticks[i] as Lang.Number).toFloat();
            var angle = (180.0 - 180.0 * tick / maximum) * Math.PI / 180.0;
            var outer = radius - pen - RideLayout.s(3);
            var inner = outer - RideLayout.s(9);
            dc.drawLine(
                cx + outer * Math.cos(angle), cy - outer * Math.sin(angle),
                cx + inner * Math.cos(angle), cy - inner * Math.sin(angle));
        }

        var edge = RideLayout.number("cadence", "radius") - RideLayout.number("cadence", "pen") / 2.0;
        var edgeY = RideLayout.number("cadence", "cy") + 16;
        label(dc, RideLayout.number("cadence", "cx") - edge, edgeY, "0", 13, "textDim");
        label(dc, RideLayout.number("cadence", "cx") + edge, edgeY, maximum.format("%d"), 13, "textDim");

        number(dc, RideLayout.centerX(), RideLayout.number("cadence", "labelY"), cadence.toString(),
            RideLayout.number("cadence", "labelSize"), cadenceColor(cadence));
        label(dc, RideLayout.centerX(), RideLayout.number("cadence", "unitY"), "KADENCE rpm",
            RideLayout.number("cadence", "unitSize"), "textDim");
    }

    // --- tachometr ----------------------------------------------------------

    function drawSpeed(dc) as Void {
        var speed = RideData.speed();
        var whole = speed.toNumber();
        var decimal = ((speed - whole) * 10.0).toNumber();
        if (decimal < 0) {
            decimal = 0;
        }

        var centerY = RideLayout.y(RideLayout.number("speed", "cy"));
        var bigFont = RideLayout.numberFont(dc, RideLayout.number("speed", "size"));
        var smallFont = RideLayout.numberFont(dc, RideLayout.number("speed", "decimalSize"));
        var wholeText = whole.toString();
        var decimalText = "." + decimal.toString();

        var wholeWidth = dc.getTextWidthInPixels(wholeText, bigFont);
        var decimalWidth = dc.getTextWidthInPixels(decimalText, smallFont);
        var left = RideLayout.x(RideLayout.centerX()) - (wholeWidth + decimalWidth) / 2;

        // Desetinné místo sedí na stejné lince jako celá čísla - o kolik níž,
        // to plyne z rozdílu výšek písma, ne z pevného odsazení.
        var drop = (dc.getFontHeight(bigFont) - dc.getFontHeight(smallFont)) / 2;

        dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, centerY, bigFont, wholeText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(left + wholeWidth, centerY + drop, smallFont, decimalText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Jednotka je pod tachometrem, takže musí uhnout pod spodní hranu jeho
        // písma. Návrhová souřadnice s tím počítá jen pro Edge 1050; jinde
        // vyjde jiný font a "km/h" by skončilo přes desetinné místo.
        var unitFont = RideLayout.textFont(dc, RideLayout.number("speed", "unitSize"));
        var unitY = centerY + (dc.getFontHeight(bigFont) + dc.getFontHeight(unitFont)) / 2;
        var designUnitY = RideLayout.y(RideLayout.number("speed", "unitY"));
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(RideLayout.centerX()), unitY > designUnitY ? unitY : designUnitY,
            unitFont, "km/h", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawSpeedStats(dc) as Void {
        var y = RideLayout.number("speedStats", "y");
        var height = RideLayout.number("speedStats", "height");
        var gap = RideLayout.number("speedStats", "gap");
        var margin = RideLayout.number("speedStats", "margin");
        var canvasWidth = RideLayout.number("canvas", "width");
        var width = (canvasWidth - 2 * margin - gap) / 2.0;

        var labels = [["PRŮMĚR", "PRŮM"], ["MAXIMUM", "MAX"]];
        var values = [RideData.averageSpeed(), RideData.maxSpeed()];
        var colors = ["accent", "warn"];

        var unitFont = RideLayout.textFont(dc, 11);
        var unitWidth = dc.getTextWidthInPixels("km/h", unitFont);
        var padding = RideLayout.x(12);

        // Obsah panelu se skládá zprava - jednotka, před ni hodnota a popiska
        // dostane, co zbude. Pevné odsazení jednotku i hodnotu překrývalo.
        for (var i = 0; i < labels.size(); i += 1) {
            var x = margin + i * (width + gap);
            var centerY = RideLayout.y(y + height / 2.0);
            var right = RideLayout.x(x + width) - padding;
            panel(dc, x, y, width, height, 10);

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, centerY + RideLayout.y(2), unitFont, "km/h",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

            var value = values[i].format("%.1f");
            var valueFont = RideLayout.numberFont(dc, 28);
            var valueRight = right - unitWidth - RideLayout.x(4);
            dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(valueRight, centerY, valueFont, value,
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

            var left = RideLayout.x(x) + padding;
            var room = valueRight - dc.getTextWidthInPixels(value, valueFont) - left - RideLayout.x(6);
            if (room <= 0) {
                continue;
            }
            var label = fitText(dc, labels[i] as Lang.Array, room, 13);
            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, centerY, label[0], label[1],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // --- prostřední pás: kompas, mapa a metriky -----------------------------

    function drawMiddle(dc, mapBehind as Lang.Boolean) as Void {
        var top = RideLayout.number("middle", "top");
        var bottom = RideLayout.number("middle", "bottom");
        var side = RideLayout.number("middle", "sideWidth");
        var margin = RideLayout.number("middle", "margin");
        var gap = RideLayout.number("middle", "gap");
        var canvasWidth = RideLayout.number("canvas", "width");

        var cellHeight = (bottom - top - gap) / 2.0;
        var mapX = margin + side + gap;
        var mapWidth = canvasWidth - 2 * (margin + side + gap);
        var rightX = canvasWidth - margin - side;

        // Bez vlastního dojezdu e-biku zbude vlevo místo, tak se kompas roztáhne
        // přes obě buňky - prázdný panel by vypadal jako chybějící údaj.
        if (RideData.ebikeNative()) {
            drawCompass(dc, margin, top, side, bottom - top);
        } else {
            drawCompass(dc, margin, top, side, cellHeight);
            drawMetric(dc, margin, top + cellHeight + gap, side, cellHeight,
                [["DOJEZD E-BIKE", "DOJEZD", "E-BIKE"], RideData.assistRangeKm().format("%.0f"),
                    "km", RideData.assistNote()],
                "ok", RideData.assistBatteryPercent() / 100.0);
        }

        var remaining = RideData.distanceToDestinationKm();
        drawMetric(dc, rightX, top, side, cellHeight,
            [["DO CÍLE"], remaining == null ? "--" : remaining.format("%.1f"), "km",
                "příjezd " + RideData.etaString()],
            "accent", null);

        drawMetric(dc, rightX, top + cellHeight + gap, side, cellHeight,
            [["NAJETO"], RideData.distanceKm().format("%.1f"), "km", null], "text", null);

        if (mapBehind) {
            drawMapFrame(dc, mapX, top, mapWidth, bottom - top);
        } else {
            drawMap(dc, mapX, top, mapWidth, bottom - top);
        }
    }

    //! @param texts [varianty titulku, hodnota, jednotka, poznámka]; poznámka
    //!        smí být null. Sbalené do pole schválně: starší jednotky (Edge 830
    //!        a spol.) víc než devět argumentů metodě nepředají.
    //! Buňka s jednou metrikou: titulek, hodnota, jednotka, proužek a poznámka.
    //!
    //! Řádky se skládají pod sebe podle změřených výšek písma a celý sloupeček
    //! se vystředí v buňce; co se nevejde, se odspodu vynechá. Pevné odsazení
    //! od okraje fungovalo jen pro vysoké buňky z Edge 1050 - na kompaktním
    //! rozvržení, kde je buňka třetinová, by řádky ležely přes sebe.
    function drawMetric(dc, x, y, width, height, texts as Lang.Array, colorName, ratio) as Void {
        panel(dc, x, y, width, height, 10);

        var cx = RideLayout.x(x + width / 2.0);
        var room = RideLayout.x(width - 8);
        var gap = RideLayout.y(4);

        var title = fitText(dc, texts[0] as Lang.Array, room, 12);
        var valueFont = RideLayout.fitNumberFont(dc, texts[1], room, 34);
        var unitFont = RideLayout.fitFont(dc, texts[2], room, 13);
        var rows = [
            [title[0], title[1], "textDim"],
            [valueFont, texts[1], colorName],
            [unitFont, texts[2], "textDim"]
        ];
        if (ratio != null) {
            rows.add([null, null, colorName]);
        }
        if (texts[3] != null) {
            rows.add([RideLayout.fitFont(dc, texts[3], room, 12), texts[3], "textDim"]);
        }

        var barHeight = RideLayout.dy(6);
        var total = 0.0;
        var heights = [];
        for (var i = 0; i < rows.size(); i += 1) {
            var row = rows[i] as Lang.Array;
            var rowHeight = row[0] == null ? barHeight : dc.getFontHeight(row[0]);
            heights.add(rowHeight);
            total += rowHeight + (i > 0 ? gap : 0);
        }

        // Odspodu ubíráme, dokud se sloupeček do buňky nevejde - poznámka je
        // postradatelnější než hodnota.
        var boxHeight = RideLayout.dy(height) - RideLayout.dy(8);
        while (rows.size() > 2 && total > boxHeight) {
            total -= (heights[heights.size() - 1] as Lang.Float) + gap;
            rows = rows.slice(0, rows.size() - 1);
            heights = heights.slice(0, heights.size() - 1);
        }

        var cursor = RideLayout.y(y + height / 2.0) - total / 2;
        for (var i = 0; i < rows.size(); i += 1) {
            var row = rows[i] as Lang.Array;
            var rowHeight = heights[i] as Lang.Float;
            if (row[0] == null) {
                dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(RideLayout.x(x + 16), cursor, RideLayout.x(width - 32), rowHeight);
                dc.setColor(RideLayout.color(row[2]), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(RideLayout.x(x + 16), cursor,
                    RideLayout.x((width - 32) * clamp(ratio)), rowHeight);
            } else {
                dc.setColor(RideLayout.color(row[2]), Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cursor + rowHeight / 2, row[0], row[1],
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            cursor += rowHeight + gap;
        }
    }

    function clamp(ratio) {
        if (ratio < 0.0) {
            return 0.0;
        }
        return ratio > 1.0 ? 1.0 : ratio;
    }

    function drawCompass(dc, x, y, width, height) as Void {
        panel(dc, x, y, width, height, 10);

        // Na nízké buňce (kompaktní rozvržení) by titulek ležel přes růžici.
        // Slovo KOMPAS je postradatelné - směr říká šipka i údaj pod ní.
        var labelHeight = dc.getFontHeight(RideLayout.textFont(dc, 12));
        var top = RideLayout.y(y);
        var titled = RideLayout.dy(height) > labelHeight * 5;
        if (titled) {
            labelIn(dc, x + width / 2.0, y + 16, width - 8, "KOMPAS", 12, "textDim");
            top += RideLayout.dy(26);
        } else {
            top += labelHeight / 3;
        }

        var heading = RideData.heading();
        var cx = RideLayout.x(x + width / 2.0);
        var bottom = RideLayout.y(y + height) - labelHeight * 1.4;
        var cy = (top + bottom) / 2;
        var span = (bottom - top) / 2;
        var radius = RideLayout.s(width / 2.0 - 14);
        if (radius > span) {
            radius = span;
        }

        dc.setPenWidth(2);
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);

        // Nahoře je vždy směr jízdy, růžice se otáčí pod ním. Vnitřní poloměry
        // jsou podílem toho vnějšího - odečítat pevný počet pixelů šlo jen
        // u velké růžice, na malé buňce by vyšly záporné.
        var names = ["S", "V", "J", "Z"];
        for (var i = 0; i < names.size(); i += 1) {
            var bearing = (i * 90 - heading) * Math.PI / 180.0;
            var ringRadius = radius * 0.78;
            dc.setColor(i == 0 ? RideLayout.color("text") : RideLayout.color("textDim"),
                Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + ringRadius * Math.sin(bearing), cy - ringRadius * Math.cos(bearing),
                RideLayout.textFont(dc, 14), names[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        var needle = radius * 0.55;
        dc.setColor(RideLayout.color("accent"), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [cx, cy - needle],
            [cx - needle * 0.42, cy + needle * 0.42],
            [cx, cy],
            [cx + needle * 0.42, cy + needle * 0.42]
        ]);

        var cardinals = ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"];
        var index = (((heading + 22.5).toNumber() % 360) / 45).toNumber();
        labelIn(dc, x + width / 2.0, y + height - 16, width - 8,
            heading.format("%d") + "° " + cardinals[index], 15, "text");
    }

    // --- mapové okno --------------------------------------------------------

    //! Mapu kreslí systém (RideMapView) - my jen orámujeme okno a přidáme
    //! proužek s nápovědou, protože kolem okna už místo není.
    function drawMapFrame(dc, x, y, width, height) as Void {
        var strip = 18;
        var hint = fitText(dc, ["MAPA · výběr = přes celou obrazovku", "MAPA · výběr", "MAPA"],
            RideLayout.x(width - 6), 11);

        dc.setColor(RideLayout.color("panel"), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(RideLayout.x(x + 1), RideLayout.y(y + height - strip),
            RideLayout.x(width - 2), RideLayout.dy(strip - 1));

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x + width / 2.0), RideLayout.y(y + height - strip / 2.0),
            hint[0], hint[1], Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRectangle(RideLayout.x(x), RideLayout.y(y), RideLayout.x(width), RideLayout.dy(height));
    }

    //! Drobečková mapa z GPS bodů pro jednotky bez kartografie.
    function drawMap(dc, x, y, width, height) as Void {
        panel(dc, x, y, width, height, 12);

        dc.setPenWidth(1);
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        for (var i = 1; i < 5; i += 1) {
            var gridY = RideLayout.y(y + height * i / 5.0);
            dc.drawLine(RideLayout.x(x + 4), gridY, RideLayout.x(x + width - 4), gridY);
        }
        for (var j = 1; j < 4; j += 1) {
            var gridX = RideLayout.x(x + width * j / 4.0);
            dc.drawLine(gridX, RideLayout.y(y + 4), gridX, RideLayout.y(y + height - 4));
        }

        var track = RideData.track();
        if (track.size() >= 2) {
            drawTrack(dc, track, x, y, width, height);
        } else {
            labelIn(dc, x + width / 2.0, y + height / 2.0, width - 8, emptyNote(), 13, "textDim");
        }

        label(dc, x + width - 16, y + 18, "S", 13, "textDim");
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(RideLayout.x(x + width - 16), RideLayout.y(y + 24),
            RideLayout.x(x + width - 16), RideLayout.y(y + 34));
    }

    //! Co napsat doprostřed, když ještě není co kreslit. Když je známo, proč
    //! místo mapy koukáme na stopu, je to užitečnější než "čekám na GPS".
    function emptyNote() as Lang.String {
        var note = RideData.mapNote();
        return note == null ? "čekám na GPS" : note;
    }

    function drawTrack(dc, track as Lang.Array, x, y, width, height) as Void {
        var padding = RideLayout.number("map", "padding");
        var first = track[0] as Lang.Array;
        var minX = first[0];
        var maxX = first[0];
        var minY = first[1];
        var maxY = first[1];

        for (var i = 1; i < track.size(); i += 1) {
            var point = track[i] as Lang.Array;
            if (point[0] < minX) { minX = point[0]; }
            if (point[0] > maxX) { maxX = point[0]; }
            if (point[1] < minY) { minY = point[1]; }
            if (point[1] > maxY) { maxY = point[1]; }
        }

        var spanX = maxX - minX;
        var spanY = maxY - minY;
        var span = spanX > spanY ? spanX : spanY;
        if (span < 1e-9) {
            span = 1e-9;
        }

        var boxWidth = RideLayout.x(width - 2 * padding);
        var boxHeight = RideLayout.dy(height - 2 * padding);
        var box = boxWidth < boxHeight ? boxWidth : boxHeight;
        var scale = box / span;
        var offsetX = RideLayout.x(x + padding) + (boxWidth - spanX * scale) / 2;
        var offsetY = RideLayout.y(y + padding) + (boxHeight - spanY * scale) / 2;

        dc.setPenWidth(RideLayout.s(RideLayout.number("map", "trackPen")).toNumber());
        dc.setColor(RideLayout.color("accent"), Graphics.COLOR_TRANSPARENT);

        var previousX = offsetX + (first[0] - minX) * scale;
        var previousY = offsetY + (maxY - first[1]) * scale;
        for (var k = 1; k < track.size(); k += 1) {
            var step = track[k] as Lang.Array;
            var pointX = offsetX + (step[0] - minX) * scale;
            var pointY = offsetY + (maxY - step[1]) * scale;
            dc.drawLine(previousX, previousY, pointX, pointY);
            previousX = pointX;
            previousY = pointY;
        }

        var marker = RideLayout.s(RideLayout.number("map", "markerRadius"));
        dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(previousX, previousY, marker);
    }

    // --- spodní lišta -------------------------------------------------------

    function drawBottom(dc) as Void {
        var y = RideLayout.number("bottom", "y");
        var height = RideLayout.number("bottom", "height");
        var margin = RideLayout.number("bottom", "margin");
        var gap = RideLayout.number("bottom", "gap");
        var canvasWidth = RideLayout.number("canvas", "width");
        var battery = RideData.assistBatteryPercent();
        var temperature = RideData.temperature();
        var ebike = !RideData.ebikeNative();
        var cells = ebike ? 4 : 3;
        var width = (canvasWidth - 2 * margin - (cells - 1) * gap) / cells;

        var climbLabels = fitPair(dc, [["NASTOUPÁNO", "SESTOUPÁNO"], ["STOUPÁNÍ", "KLESÁNÍ"]],
            RideLayout.x(width - 8), 11);
        var titles = [[climbLabels[0]], [climbLabels[1]], [weatherLabel()]];
        var values = [
            RideData.ascent().toString() + " m",
            RideData.descent().toString() + " m",
            temperature == null ? "--" : temperature.toString() + "°C"
        ];
        var colors = ["warn", "cold", "text"];

        if (ebike) {
            titles = [["E-BIKE"], titles[0], titles[1], titles[2]];
            values = [battery.toString() + "%", values[0], values[1], values[2]];
            colors = [battery > 30 ? "ok" : "danger", colors[0], colors[1], colors[2]];
        }

        // Titulek a hodnota se staví od středu buňky podle změřených výšek;
        // u baterie se pod ně vejde ještě proužek. Pevné odsazení od horní
        // hrany fungovalo jen pro vysokou buňku z Edge 1050.
        var barHeight = RideLayout.dy(4);
        var rowGap = RideLayout.y(3);

        for (var i = 0; i < titles.size(); i += 1) {
            var x = margin + i * (width + gap);
            var cx = RideLayout.x(x + width / 2.0);
            var room = RideLayout.x(width - 8);
            panel(dc, x, y, width, height, 10);

            var title = fitText(dc, titles[i] as Lang.Array, room, 11);
            var valueFont = RideLayout.fitFont(dc, values[i], room, 21);
            var titleHeight = dc.getFontHeight(title[0]);
            var valueHeight = dc.getFontHeight(valueFont);
            var withBar = ebike && i == 0;
            var total = titleHeight + rowGap + valueHeight + (withBar ? rowGap + barHeight : 0);
            var cursor = RideLayout.y(y + height / 2.0) - total / 2;

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cursor + titleHeight / 2, title[0], title[1],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            cursor += titleHeight + rowGap;

            dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cursor + valueHeight / 2, valueFont, values[i],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            cursor += valueHeight + rowGap;

            if (withBar) {
                dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(RideLayout.x(x + 12), cursor, RideLayout.x(width - 24), barHeight);
                dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(RideLayout.x(x + 12), cursor,
                    RideLayout.x((width - 24) * clamp(battery / 100.0)), barHeight);
            }
        }

        drawWeatherIcon(dc, margin + (cells - 1) * (width + gap) + 14, y + height / 2.0 + 2);
    }

    function weatherLabel() {
        var condition = RideData.weatherCondition();
        if (condition == null) {
            return "POČASÍ";
        }
        if (condition == Weather.CONDITION_CLEAR || condition == Weather.CONDITION_MOSTLY_CLEAR) {
            return "JASNO";
        }
        if (condition == Weather.CONDITION_RAIN || condition == Weather.CONDITION_LIGHT_RAIN ||
            condition == Weather.CONDITION_HEAVY_RAIN || condition == Weather.CONDITION_SHOWERS) {
            return "DÉŠŤ";
        }
        if (condition == Weather.CONDITION_SNOW || condition == Weather.CONDITION_LIGHT_SNOW ||
            condition == Weather.CONDITION_HEAVY_SNOW) {
            return "SNÍH";
        }
        return "OBLAČNO";
    }

    function drawWeatherIcon(dc, x, y) as Void {
        var cx = RideLayout.x(x);
        var cy = RideLayout.y(y);
        var unit = RideLayout.s(1);
        var condition = RideData.weatherCondition();

        if (condition != null &&
            (condition == Weather.CONDITION_CLEAR || condition == Weather.CONDITION_MOSTLY_CLEAR)) {
            dc.setColor(RideLayout.color("warn"), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 7 * unit);
            return;
        }

        dc.setColor(RideLayout.color("warn"), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx + 4 * unit, cy - 5 * unit, 5 * unit);
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - 4 * unit, cy + unit, 5 * unit);
        dc.fillCircle(cx + 3 * unit, cy + unit, 6 * unit);
    }
}
