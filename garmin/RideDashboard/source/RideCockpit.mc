using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;

//! Styl přístrojového štítu auta: mapa vyplňuje celou obrazovku a nad ní jsou
//! dva překryvy - nahoře rychlost s kadencí a kompasovou páskou, dole dojezd,
//! převýšení a počasí. Překryvy se směrem k mapě rozplývají, aby mezi
//! palubovkou a kartografií nebyla tvrdá hrana. Geometrie je v sekci "cockpit"
//! v layout.json.
module RideCockpit {

    var CARDINALS as Lang.Array<Lang.String> = ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"];

    //: Na kolik pruhů se rozpadne rozplývavý okraj překryvu.
    const SCRIM_STEPS = 24;

    function draw(dc, mapBehind as Lang.Boolean) as Void {
        RideLayout.prepare(dc);

        if (mapBehind) {
            // Přehledová stopa dává smysl jen nad zazoomovanou mapou - a jen
            // tam, kde na ni po překryvech zbude kus mapy.
            if (RideLayout.feature("inset")) {
                drawInset(dc);
            }
        } else {
            drawFallbackTrack(dc);
        }

        drawTop(dc);
        drawBottom(dc);
    }

    //! Bez kartografie zaplní místo mezi překryvy jen projetá stopa.
    function drawFallbackTrack(dc) as Void {
        var focus = RideLayout.group("cockpit", "focus");
        var top = RideLayout.at(focus, "top");
        var height = RideLayout.at(focus, "bottom") - top;
        var width = RideLayout.number("canvas", "width");

        dc.setColor(RideLayout.color("background"), RideLayout.color("background"));
        dc.clear();

        var track = RideData.track();
        if (track.size() >= 2) {
            RideChrome.drawTrack(dc, track, 0, top, width, height);
        } else {
            RideChrome.label(dc, width / 2.0, top + height / 2.0, "čekám na GPS", 13, "textDim");
        }
    }

    // --- kreslicí pomocníky -------------------------------------------------

    //! Překryv nad mapou, který se na jedné straně rozplyne. Průhlednost umí až
    //! API 4.0; bez ní zůstane prostý neprůhledný pruh.
    function scrim(dc, y, height, fadeAtBottom as Lang.Boolean) as Void {
        var spec = RideLayout.group("cockpit", "scrim");
        var color = spec["color"] as Lang.Number;
        var width = dc.getWidth();

        if (!(Graphics has :createColor)) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, RideLayout.y(y), width, RideLayout.y(height));
            return;
        }

        var alpha = spec["alpha"] as Lang.Number;
        var red = (color >> 16) & 0xFF;
        var green = (color >> 8) & 0xFF;
        var blue = color & 0xFF;
        var fade = RideLayout.at(spec, "fade");

        dc.setColor(Graphics.createColor(alpha, red, green, blue), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, RideLayout.y(fadeAtBottom ? y : y + fade), width,
            RideLayout.y(height - fade));

        var step = fade / SCRIM_STEPS;
        for (var i = 0; i < SCRIM_STEPS; i += 1) {
            var ratio = (i + 1.0) / SCRIM_STEPS;
            var bandAlpha = (alpha * Math.pow(1.0 - ratio, 1.6)).toNumber();
            var top = fadeAtBottom
                ? y + height - fade + i * step
                : y + fade - (i + 1) * step;
            dc.setColor(Graphics.createColor(bandAlpha, red, green, blue), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, RideLayout.y(top), width, RideLayout.y(step) + 1);
        }
    }

    function card(dc, x, y, width, height, radius) as Void {
        dc.setColor(RideLayout.color("panel"), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(RideLayout.x(x), RideLayout.y(y),
            RideLayout.x(width), RideLayout.y(height), RideLayout.s(radius));
    }

    function pill(dc, x, y, width, height) as Void {
        card(dc, x, y, width, height, height / 2.0);
    }

    //! Tříčtvrteční oblouk se zakulacenými konci.
    function gauge(dc, cx, cy, radius, pen, ratio, colorName) as Void {
        // Garmin měří úhly proti směru hodinových ručiček od tří hodin, takže
        // oblouk vede z levého dolního rohu (225) po směru do pravého (315).
        var start = 225.0;
        var span = 270.0;

        dc.setPenWidth(pen.toNumber());
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 225, 315);

        var value = ratio;
        if (value < 0.0) {
            value = 0.0;
        }
        if (value > 1.0) {
            value = 1.0;
        }
        var sweep = span * value;
        if (sweep < 1.0) {
            return;
        }

        var end = start - sweep;
        if (end < 0.0) {
            end += 360.0;
        }
        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, start.toNumber(), end.toNumber());

        cap(dc, cx, cy, radius, pen, start);
        cap(dc, cx, cy, radius, pen, start - sweep);
    }

    function cap(dc, cx, cy, radius, pen, degrees) as Void {
        var radians = degrees * Math.PI / 180.0;
        dc.fillCircle(cx + radius * Math.cos(radians), cy - radius * Math.sin(radians), pen / 2.0);
    }

    // --- horní překryv ------------------------------------------------------

    function drawTop(dc) as Void {
        scrim(dc, 0, RideLayout.at(RideLayout.group("cockpit", "top"), "height"), true);

        if (RideLayout.feature("tape")) {
            drawTape(dc);
        }
        drawCadence(dc);
        drawSpeed(dc);
        drawClock(dc);
        if (RideLayout.feature("chips")) {
            drawChips(dc);
        }
    }

    //! Kompasová páska přes celou šířku - v autě jsou tady názvy ulic.
    function drawTape(dc) as Void {
        var tape = RideLayout.group("cockpit", "tape");
        var centerY = RideLayout.at(tape, "y") + RideLayout.at(tape, "height") / 2.0;
        var spacing = RideLayout.at(tape, "spacing");
        var heading = RideData.heading();
        var center = RideLayout.centerX();
        var first = ((heading - 70) / 10).toNumber() * 10;

        for (var step = first; step <= heading + 70; step += 10) {
            var bearing = step % 360;
            if (bearing < 0) {
                bearing += 360;
            }
            var x = center + (step - heading) * spacing;

            if (bearing % 45 == 0) {
                RideChrome.label(dc, x, centerY, CARDINALS[bearing / 45], 13, "text");
            } else if (bearing % 30 == 0) {
                RideChrome.label(dc, x, centerY, bearing.toString(), 11, "textDim");
            } else {
                dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawLine(RideLayout.x(x), RideLayout.y(centerY - 4),
                    RideLayout.x(x), RideLayout.y(centerY + 4));
            }
        }

        dc.setColor(RideLayout.color("accent"), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [RideLayout.x(center), RideLayout.y(centerY + 11)],
            [RideLayout.x(center - 5), RideLayout.y(centerY + 17)],
            [RideLayout.x(center + 5), RideLayout.y(centerY + 17)]
        ]);
    }

    //! Kadence jako budík vlevo - obdoba značky s limitem v autě.
    function drawCadence(dc) as Void {
        var spec = RideLayout.group("cockpit", "cadence");
        var designX = RideLayout.at(spec, "cx");
        var designY = RideLayout.at(spec, "cy");
        var cadence = RideData.cadence();
        var colorName = RideChrome.cadenceColor(cadence);

        gauge(dc, RideLayout.x(designX), RideLayout.y(designY),
            RideLayout.s(RideLayout.at(spec, "radius")),
            RideLayout.s(RideLayout.at(spec, "pen")),
            cadence / RideLayout.at(spec, "max"), colorName);

        RideChrome.number(dc, designX, designY - 6, cadence.toString(), 28, colorName);
        RideChrome.label(dc, designX, designY + 17, "RPM", 10, "textDim");
    }

    function drawSpeed(dc) as Void {
        var spec = RideLayout.group("cockpit", "speed");
        var speed = RideData.speed();
        var whole = speed.toNumber();
        var decimal = ((speed - whole) * 10.0).toNumber();
        if (decimal < 0) {
            decimal = 0;
        }

        var centerY = RideLayout.y(RideLayout.at(spec, "cy"));
        var bigFont = RideLayout.numberFont(dc, RideLayout.at(spec, "size"));
        var smallFont = RideLayout.numberFont(dc, RideLayout.at(spec, "decimalSize"));
        var wholeText = whole.toString();
        var decimalText = "." + decimal.toString();

        var wholeWidth = dc.getTextWidthInPixels(wholeText, bigFont);
        var decimalWidth = dc.getTextWidthInPixels(decimalText, smallFont);
        var left = RideLayout.x(RideLayout.at(spec, "cx")) - (wholeWidth + decimalWidth) / 2;

        // Desetinné místo i jednotka sedí na stejné lince jako celá čísla -
        // o kolik níž, to plyne z rozdílu výšek písma, ne z pevného odsazení.
        var unitFont = RideLayout.textFont(dc, 12);
        var bigHeight = dc.getFontHeight(bigFont);
        var drop = (bigHeight - dc.getFontHeight(smallFont)) / 2;

        dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, centerY, bigFont, wholeText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(RideLayout.color("accent"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + wholeWidth, centerY + drop, smallFont, decimalText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + wholeWidth + decimalWidth + RideLayout.x(8),
            centerY + (bigHeight - dc.getFontHeight(unitFont)) / 2, unitFont, "km/h",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Hodiny a pod nimi stavový řádek. Řádek se skládá zprava doleva podle
    //! změřených šířek - pevné odsazení by při nejmenším Garmin fontu (a ten je
    //! větší, než návrh čeká) nechalo procenta baterie ležet přes nápis GPS.
    function drawClock(dc) as Void {
        var spec = RideLayout.group("cockpit", "clock");
        var right = RideLayout.x(RideLayout.at(spec, "x"));
        var statusY = RideLayout.y(RideLayout.at(spec, "statusY"));
        var font = RideLayout.textFont(dc, 10);
        var gap = RideLayout.x(8);

        dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(right, RideLayout.y(RideLayout.at(spec, "y")),
            RideLayout.numberFont(dc, 24), RideData.clockString(),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        var battery = RideData.deviceBatteryPercent().toString() + " %";
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(right, statusY, font, battery,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        var gpsRight = right - dc.getTextWidthInPixels(battery, font) - gap;
        dc.drawText(gpsRight, statusY, font, "GPS",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        var dot = RideLayout.s(3.5);
        dc.setColor(RideData.hasFix() ? RideLayout.color("ok") : RideLayout.color("textDim"),
            Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gpsRight - dc.getTextWidthInPixels("GPS", font) - dot - gap / 2, statusY, dot);
    }

    //! Pilulky s průměrnou a maximální rychlostí. Obsah se skládá zprava:
    //! nejdřív jednotka, před ni hodnota a popiska dostane, co zbude - když
    //! nezbude nic (malý displej), vynechá se.
    function drawChips(dc) as Void {
        var spec = RideLayout.group("cockpit", "chips");
        var y = RideLayout.at(spec, "y");
        var height = RideLayout.at(spec, "height");
        var gap = RideLayout.at(spec, "gap");
        var margin = RideLayout.at(spec, "margin");
        var width = (RideLayout.number("canvas", "width") - 2 * margin - gap) / 2.0;
        var padding = RideLayout.x(14);
        var unitFont = RideLayout.textFont(dc, 10);
        var valueFont = RideLayout.numberFont(dc, 19);
        var unitWidth = dc.getTextWidthInPixels("km/h", unitFont);

        var titles = [["PRŮMĚR", "PRŮM"], ["MAX"]];
        var values = [RideData.averageSpeed(), RideData.maxSpeed()];
        var colors = ["accent", "warn"];

        for (var i = 0; i < titles.size(); i += 1) {
            var x = margin + i * (width + gap);
            var centerY = RideLayout.y(y + height / 2.0);
            var right = RideLayout.x(x + width) - padding;
            pill(dc, x, y, width, height);

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(right, centerY, unitFont, "km/h",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

            var value = values[i].format("%.1f");
            var valueRight = right - unitWidth - RideLayout.x(4);
            dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(valueRight, centerY, valueFont, value,
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

            var left = RideLayout.x(x) + padding;
            var room = valueRight - dc.getTextWidthInPixels(value, valueFont) - left - RideLayout.x(6);
            if (room <= 0) {
                continue;
            }
            var title = RideChrome.fitText(dc, titles[i] as Lang.Array, room, 10);
            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, centerY, title[0], title[1],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // --- spodní překryv -----------------------------------------------------

    function drawBottom(dc) as Void {
        var spec = RideLayout.group("cockpit", "bottom");
        scrim(dc, RideLayout.at(spec, "y"), RideLayout.at(spec, "height"), false);

        var margin = RideLayout.at(spec, "margin");
        var canvasWidth = RideLayout.number("canvas", "width");

        drawSummary(dc, margin, canvasWidth);
        drawStatus(dc, margin, canvasWidth);
        drawBatteryStrip(dc, canvasWidth);
    }

    //! Tři velké údaje oddělené vlásovými linkami.
    function drawSummary(dc, margin, canvasWidth) as Void {
        var spec = RideLayout.group("cockpit", "rowA");
        var titleY = RideLayout.at(spec, "titleY");
        var valueY = RideLayout.at(spec, "valueY");
        var dividerTop = RideLayout.at(spec, "dividerTop");
        var dividerHeight = RideLayout.at(spec, "dividerHeight");
        var width = (canvasWidth - 2 * margin) / 3.0;

        var remaining = RideData.distanceToDestinationKm();
        var titles = ["DOJEZD E-BIKE", "DO CÍLE", "NAJETO"];
        var values = [
            RideData.assistRangeKm().format("%.0f"),
            remaining == null ? "--" : remaining.format("%.1f"),
            RideData.distanceKm().format("%.1f")
        ];
        var units = [RideData.assistRangeUnit(), "km · " + RideData.etaString(), "km"];
        var colors = ["ok", "accent", "text"];

        for (var i = 0; i < titles.size(); i += 1) {
            var cx = margin + width * (i + 0.5);

            if (i > 0) {
                var lineX = RideLayout.x(margin + width * i);
                dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawLine(lineX, RideLayout.y(dividerTop), lineX, RideLayout.y(dividerTop + dividerHeight));
            }

            RideChrome.labelIn(dc, cx, titleY, width - 4, titles[i], 10, "textDim");

            // Hodnota s jednotkou tvoří jeden blok na střed sloupce, celý
            // zmenšený tak, aby nepřelezl do vedlejšího.
            var room = RideLayout.x(width - 6);
            var pad = RideLayout.x(5);
            var font = RideLayout.fitNumberFont(dc, values[i], room * 0.7, 32);
            var valueWidth = dc.getTextWidthInPixels(values[i], font);
            var unit = fitUnit(dc, units[i], room - valueWidth - pad);
            var unitFont = unit[0];
            var unitWidth = dc.getTextWidthInPixels(unit[1], unitFont);
            var left = RideLayout.x(cx) - (valueWidth + pad + unitWidth) / 2;

            dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, RideLayout.y(valueY), font, values[i],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + valueWidth + pad, RideLayout.y(valueY + 6), unitFont, unit[1],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Jednotka do zbylého místa vedle hodnoty jako [font, text].
    //!
    //! Přívažek za jednotkou ("km · odhad", "km · 15:04") je hezký, dokud se
    //! vejde; na úzkém displeji z něj zbude holé "km". Zdroj dojezdu je pak
    //! stejně ve stavovém řádku pod tím.
    function fitUnit(dc, text, room) as Lang.Array {
        var separator = text.find(" ·");
        var choices = separator == null ? [text] : [text, text.substring(0, separator)];
        return RideChrome.fitText(dc, choices, room, 10);
    }

    //! Řádek se stavem: baterie e-biku, převýšení a počasí. Sloupce se dělí
    //! rovným dílem přes celou šířku, popisky se do svého dílu vejdou zmenšením
    //! fontu - dřív měly pevné souřadnice a "SESTOUPÁNO" leželo přes počasí.
    function drawStatus(dc, margin, canvasWidth) as Void {
        var spec = RideLayout.group("cockpit", "rowB");
        var y = RideLayout.at(spec, "y");
        var labelY = RideLayout.at(spec, "labelY");
        var battery = RideData.assistBatteryPercent();
        var temperature = RideData.temperature();
        var width = (canvasWidth - 2 * margin) / 4.0;

        // Popisky dostanou dvě varianty: na čtvrtinu úzkého displeje se
        // "SESTOUPÁNO" nevejde ani nejmenším fontem, ale šipka nahoru a dolů
        // to řekne taky - proto je druhá varianta prázdná.
        value(dc, [margin, y, labelY, width], battery.toString() + " %",
            [RideData.assistBatteryLabel(), RideData.assistShortLabel()],
            battery > 30 ? "ok" : "danger");
        climb(dc, [margin + width, y, labelY, width], true, RideData.ascent(),
            ["NASTOUPÁNO", "STOUPÁNÍ"], "warn");
        climb(dc, [margin + 2 * width, y, labelY, width], false, RideData.descent(),
            ["SESTOUPÁNO", "KLESÁNÍ"], "cold");

        var weatherX = margin + 3 * width;
        RideChrome.drawWeatherIcon(dc, weatherX + 8, y - 2);
        value(dc, [weatherX + 20, y, labelY, width - 20],
            temperature == null ? "--" : temperature.toString() + " °C",
            [RideChrome.weatherLabel()], "text");
    }

    //! @param box [x, y hodnoty, y popisky, šířka sloupce] v návrhových pixelech
    //! @param titles varianty popisky od nejdelší; vejít se musí aspoň prázdná
    function value(dc, box as Lang.Array, text, titles as Lang.Array, colorName) as Void {
        valueText(dc, box[0], box[1], box[3], text, colorName);
        valueLabel(dc, box[0], box[2], box[3], titles);
    }

    function valueText(dc, x, y, width, text, colorName) as Void {
        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x), RideLayout.y(y),
            RideLayout.fitNumberFont(dc, text, RideLayout.x(width), 17), text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function valueLabel(dc, x, y, width, titles as Lang.Array) as Void {
        // Mezi sloupci musí zbýt mezera, jinak popisky navazují jedna na druhou
        // bez pauzy a čtou se jako jedno slovo.
        var title = RideChrome.fitText(dc, titles, RideLayout.x(width - 8), 10);
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x), RideLayout.y(y), title[0], title[1],
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Šipky se kreslí, ne píšou - Garmin fonty znak "↑" nemají.
    //! Šipka odsune jen hodnotu; popiska pod ní smí začít u kraje sloupce, ať
    //! má na dlouhé "SESTOUPÁNO" co nejvíc místa.
    function climb(dc, box as Lang.Array, up, meters, titles, colorName) as Void {
        var cx = RideLayout.x(box[0] + 5);
        var cy = RideLayout.y(box[1]);
        var size = RideLayout.s(5);

        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        if (up) {
            dc.fillPolygon([[cx, cy - size], [cx - size, cy + size], [cx + size, cy + size]]);
        } else {
            dc.fillPolygon([[cx, cy + size], [cx - size, cy - size], [cx + size, cy - size]]);
        }

        valueText(dc, box[0] + 14, box[1], box[3] - 14, meters.toString() + " m", colorName);
        valueLabel(dc, box[0], box[2], box[3], titles);
    }

    //! Baterie e-biku jako tenký proužek přes celou spodní hranu.
    function drawBatteryStrip(dc, canvasWidth) as Void {
        var spec = RideLayout.group("cockpit", "battery");
        var battery = RideData.assistBatteryPercent();
        RideChrome.bar(dc, 0, RideLayout.at(spec, "y"), canvasWidth, RideLayout.at(spec, "height"),
            battery / 100.0, battery > 30 ? "ok" : "danger");
    }

    // --- přehledová stopa v rohu mapy ---------------------------------------

    function drawInset(dc) as Void {
        var spec = RideLayout.group("cockpit", "inset");
        var x = RideLayout.at(spec, "x");
        var width = RideLayout.at(spec, "width");
        var height = RideLayout.at(spec, "height");
        var y = RideLayout.at(RideLayout.group("cockpit", "bottom"), "y")
            - RideLayout.at(spec, "bottomGap") - height;

        card(dc, x, y, width, height, RideLayout.at(spec, "radius"));

        var track = RideData.track();
        if (track.size() >= 2) {
            RideChrome.drawTrack(dc, track, x, y, width, height);
        } else {
            RideChrome.label(dc, x + width / 2.0, y + height / 2.0, "čekám na GPS", 11, "textDim");
        }

        RideChrome.label(dc, x + width / 2.0, y + 13, "CELÁ TRASA", 10, "textDim");
    }
}
