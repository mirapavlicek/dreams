using Toybox.Graphics;
using Toybox.Lang;

//! Styl přístrojového štítu auta: mapa vyplňuje celou obrazovku a nad ní jsou
//! dva pruhy - nahoře rychlost s kadencí a kompasovou páskou, dole dojezd,
//! převýšení a počasí. Geometrie je v sekci "cockpit" v layout.json.
module RideCockpit {

    var CARDINALS as Lang.Array<Lang.String> = ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"];

    function draw(dc, mapBehind as Lang.Boolean) as Void {
        RideLayout.prepare(dc);

        if (mapBehind) {
            // Přehledová stopa dává smysl jen nad zazoomovanou mapou.
            drawInset(dc);
        } else {
            var top = RideLayout.at(RideLayout.group("cockpit", "top"), "height");
            var bottom = RideLayout.at(RideLayout.group("cockpit", "bottom"), "y");
            dc.setColor(RideLayout.color("background"), RideLayout.color("background"));
            dc.clear();
            RideChrome.drawMap(dc, 0, top, RideLayout.number("canvas", "width"), bottom - top);
        }

        drawTop(dc);
        drawBottom(dc);
    }

    //! Pruh nad mapou. Průhlednost umí až API 4.0, jinak je prostě neprůhledný.
    function band(dc, x, y, width, height, radius) as Void {
        var spec = RideLayout.section("cockpit");
        var color = spec["bandColor"] as Lang.Number;

        if (Graphics has :createColor) {
            color = Graphics.createColor((spec["bandAlpha"] as Lang.Number),
                (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF);
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(RideLayout.x(x), RideLayout.y(y),
            RideLayout.x(width), RideLayout.y(height), RideLayout.s(radius));
    }

    // --- horní pruh ---------------------------------------------------------

    function drawTop(dc) as Void {
        var top = RideLayout.group("cockpit", "top");
        var radius = RideLayout.at(top, "radius");
        var canvasWidth = RideLayout.number("canvas", "width");

        // Pruh přetéká přes horní a boční okraj, ať jsou zakulacené jen rohy dole.
        band(dc, -radius, -radius, canvasWidth + 2 * radius,
            RideLayout.at(top, "height") + radius, radius);

        drawTape(dc);
        drawCadenceBadge(dc);
        drawSpeed(dc);
        drawClock(dc);
        drawChips(dc);
    }

    //! Kompasová páska přes celou šířku - v autě jsou tady názvy ulic.
    function drawTape(dc) as Void {
        var tape = RideLayout.group("cockpit", "tape");
        var centerY = RideLayout.at(tape, "y") + RideLayout.at(tape, "height") / 2.0;
        var spacing = RideLayout.at(tape, "spacing");
        var heading = RideData.heading();
        var first = ((heading - 70) / 10).toNumber() * 10;

        for (var step = first; step <= heading + 70; step += 10) {
            var bearing = step % 360;
            if (bearing < 0) {
                bearing += 360;
            }
            var x = 240 + (step - heading) * spacing;

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
            [RideLayout.x(240), RideLayout.y(centerY + 11)],
            [RideLayout.x(235), RideLayout.y(centerY + 17)],
            [RideLayout.x(245), RideLayout.y(centerY + 17)]
        ]);
    }

    //! Kadence jako kruhový budík vlevo - obdoba značky s limitem v autě.
    function drawCadenceBadge(dc) as Void {
        var spec = RideLayout.group("cockpit", "cadence");
        var designX = RideLayout.at(spec, "cx");
        var designY = RideLayout.at(spec, "cy");
        var cx = RideLayout.x(designX);
        var cy = RideLayout.y(designY);
        var radius = RideLayout.s(RideLayout.at(spec, "radius"));
        var pen = RideLayout.s(RideLayout.at(spec, "pen"));
        var cadence = RideData.cadence();
        var colorName = RideChrome.cadenceColor(cadence);

        dc.setPenWidth(pen.toNumber());
        dc.setColor(RideLayout.color("panelEdge"), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);

        var ratio = cadence / RideLayout.at(spec, "max");
        if (ratio > 1.0) {
            ratio = 1.0;
        }
        var sweep = 358.0 * ratio;
        if (sweep > 1.0) {
            var end = 90.0 - sweep;
            if (end < 0.0) {
                end += 360.0;
            }
            dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, end);
        }

        RideChrome.number(dc, designX, designY - 4, cadence.toString(), 30, colorName);
        RideChrome.label(dc, designX, designY + 20, "rpm", 11, "textDim");
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

        dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, centerY, bigFont, wholeText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(left + wholeWidth, centerY + RideLayout.y(18), smallFont, decimalText,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + wholeWidth + decimalWidth + RideLayout.x(6), centerY + RideLayout.y(22),
            RideLayout.textFont(dc, 15), "km/h",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawClock(dc) as Void {
        var spec = RideLayout.group("cockpit", "clock");
        var x = RideLayout.at(spec, "x");
        var statusY = RideLayout.at(spec, "statusY");

        RideChrome.number(dc, x, RideLayout.at(spec, "y"), RideData.clockString(), 26, "text");

        dc.setColor(RideData.hasFix() ? RideLayout.color("ok") : RideLayout.color("textDim"),
            Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x - 26), RideLayout.y(statusY), RideLayout.textFont(dc, 11), "GPS",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x + 30), RideLayout.y(statusY), RideLayout.textFont(dc, 11),
            RideData.deviceBatteryPercent().toString() + "%",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawChips(dc) as Void {
        var spec = RideLayout.group("cockpit", "chips");
        var y = RideLayout.at(spec, "y");
        var height = RideLayout.at(spec, "height");
        var gap = RideLayout.at(spec, "gap");
        var margin = RideLayout.at(spec, "margin");
        var radius = RideLayout.at(spec, "radius");
        var width = (RideLayout.number("canvas", "width") - 2 * margin - gap) / 2.0;

        var titles = ["PRŮMĚR", "MAX"];
        var values = [RideData.averageSpeed(), RideData.maxSpeed()];
        var colors = ["accent", "warn"];

        for (var i = 0; i < titles.size(); i += 1) {
            var x = margin + i * (width + gap);
            var centerY = y + height / 2.0;
            RideChrome.panel(dc, x, y, width, height, radius);

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(RideLayout.x(x + 12), RideLayout.y(centerY), RideLayout.textFont(dc, 11), titles[i],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(RideLayout.x(x + width - 38), RideLayout.y(centerY), RideLayout.numberFont(dc, 18),
                values[i].format("%.1f"), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(RideLayout.x(x + width - 10), RideLayout.y(centerY + 1), RideLayout.textFont(dc, 10),
                "km/h", Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // --- spodní pruh --------------------------------------------------------

    function drawBottom(dc) as Void {
        var spec = RideLayout.group("cockpit", "bottom");
        var y = RideLayout.at(spec, "y");
        var radius = RideLayout.at(spec, "radius");
        var margin = RideLayout.at(spec, "margin");
        var canvasWidth = RideLayout.number("canvas", "width");

        band(dc, -radius, y, canvasWidth + 2 * radius,
            RideLayout.at(spec, "height") + radius, radius);

        drawSummary(dc, margin, canvasWidth);
        drawStatus(dc, margin, canvasWidth);
    }

    //! Tři velké údaje: dojezd, vzdálenost do cíle a najeté kilometry.
    function drawSummary(dc, margin, canvasWidth) as Void {
        var spec = RideLayout.group("cockpit", "rowA");
        var titleY = RideLayout.at(spec, "titleY");
        var valueY = RideLayout.at(spec, "valueY");
        var width = (canvasWidth - 2 * margin) / 3.0;

        var remaining = RideData.distanceToDestinationKm();
        var titles = ["DOJEZD E-BIKE", "DO CÍLE", "NAJETO"];
        var values = [
            RideData.assistRangeKm().format("%.0f"),
            remaining == null ? "--" : remaining.format("%.1f"),
            RideData.distanceKm().format("%.1f")
        ];
        var units = ["km", "km · " + RideData.etaString(), "km"];
        var colors = ["ok", "accent", "text"];

        for (var i = 0; i < titles.size(); i += 1) {
            var cx = margin + width * (i + 0.5);
            RideChrome.label(dc, cx, titleY, titles[i], 11, "textDim");

            var font = RideLayout.numberFont(dc, 30);
            var valueWidth = dc.getTextWidthInPixels(values[i], font);
            var left = RideLayout.x(cx) - valueWidth / 2;

            dc.setColor(RideLayout.color(colors[i]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, RideLayout.y(valueY), font, values[i],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left + valueWidth + RideLayout.x(5), RideLayout.y(valueY + 5),
                RideLayout.textFont(dc, 11), units[i],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Řádek se stavem: baterie e-biku, převýšení a počasí.
    function drawStatus(dc, margin, canvasWidth) as Void {
        var spec = RideLayout.group("cockpit", "rowB");
        var y = RideLayout.at(spec, "y");
        var barY = RideLayout.at(spec, "barY");
        var battery = RideData.assistBatteryPercent();
        var batteryColor = battery > 30 ? "ok" : "danger";
        var temperature = RideData.temperature();

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(margin), RideLayout.y(y), RideLayout.textFont(dc, 11), "E-BIKE",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(RideLayout.color(batteryColor), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(margin + 52), RideLayout.y(y), RideLayout.numberFont(dc, 17),
            battery.toString() + "%", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        RideChrome.bar(dc, margin, barY, 100, 5, battery / 100.0, batteryColor);

        drawClimb(dc, 196, y, barY, true, RideData.ascent(), "NASTOUPÁNO", "warn");
        drawClimb(dc, 302, y, barY, false, RideData.descent(), "SESTOUPÁNO", "cold");

        RideChrome.drawWeatherIcon(dc, 400, y);
        dc.setColor(RideLayout.color("text"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(canvasWidth - margin), RideLayout.y(y), RideLayout.numberFont(dc, 19),
            temperature == null ? "--" : temperature.toString() + "°C",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(canvasWidth - margin), RideLayout.y(barY + 2),
            RideLayout.textFont(dc, 10), RideChrome.weatherLabel(),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Šipky se kreslí, ne píšou - Garmin fonty znak "↑" nemají.
    function drawClimb(dc, x, y, labelY, up, meters, title, colorName) as Void {
        var cx = RideLayout.x(x);
        var cy = RideLayout.y(y);
        var size = RideLayout.s(5);

        dc.setColor(RideLayout.color(colorName), Graphics.COLOR_TRANSPARENT);
        if (up) {
            dc.fillPolygon([[cx, cy - size], [cx - size, cy + size], [cx + size, cy + size]]);
        } else {
            dc.fillPolygon([[cx, cy + size], [cx - size, cy - size], [cx + size, cy - size]]);
        }
        dc.drawText(RideLayout.x(x + 10), cy, RideLayout.numberFont(dc, 15), meters.toString() + " m",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        RideChrome.label(dc, x + 16, labelY + 2, title, 10, "textDim");
    }

    // --- přehledová stopa v rohu mapy ---------------------------------------

    function drawInset(dc) as Void {
        var spec = RideLayout.group("cockpit", "inset");
        var x = RideLayout.at(spec, "x");
        var width = RideLayout.at(spec, "width");
        var height = RideLayout.at(spec, "height");
        var y = RideLayout.at(RideLayout.group("cockpit", "bottom"), "y")
            - RideLayout.at(spec, "bottomGap") - height;

        RideChrome.panel(dc, x, y, width, height, RideLayout.at(spec, "radius"));

        var track = RideData.track();
        if (track.size() >= 2) {
            RideChrome.drawTrack(dc, track, x, y, width, height);
        } else {
            RideChrome.label(dc, x + width / 2.0, y + height / 2.0, "čekám na GPS", 11, "textDim");
        }

        dc.setColor(RideLayout.color("textDim"), Graphics.COLOR_TRANSPARENT);
        dc.drawText(RideLayout.x(x + width - 8), RideLayout.y(y + 12), RideLayout.textFont(dc, 10),
            "CELÁ TRASA", Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
