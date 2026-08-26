using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;

//! Rozvržení je popsané v resources/json/layout.json v pixelech návrhového
//! plátna 480x800. Tenhle modul ho načte a přepočítá na skutečný displej,
//! takže stejná čísla platí pro Edge 1050 i menší jednotky.
module RideLayout {

    var mLayout = null;
    var mScaleX = 1.0;
    var mScaleY = 1.0;
    var mScale = 1.0;

    //: Poměr mezi výškou Garmin fontu a výškou číslic v návrhu.
    const FONT_HEIGHT_RATIO = 1.3;

    function layout() as Lang.Dictionary {
        if (mLayout == null) {
            mLayout = Application.loadResource(Rez.JsonData.Layout);
        }
        return mLayout as Lang.Dictionary;
    }

    function section(name) as Lang.Dictionary {
        return layout()[name] as Lang.Dictionary;
    }

    function value(sectionName, key) {
        return section(sectionName)[key];
    }

    //! Vnořená skupina, třeba layout()["cockpit"]["tape"].
    function group(sectionName, key) as Lang.Dictionary {
        return section(sectionName)[key] as Lang.Dictionary;
    }

    function at(dictionary as Lang.Dictionary, key) {
        return (dictionary[key] as Lang.Number).toFloat();
    }

    function number(sectionName, key) {
        return (section(sectionName)[key] as Lang.Number).toFloat();
    }

    function color(name) {
        return section("colors")[name];
    }

    //! Volitelné prvky palubovky. Malé displeje si část z nich v kompaktním
    //! rozvržení vypnou - na 246x322 se kompasová páska ani pilulky s průměrem
    //! nevejdou tak, aby se daly přečíst.
    function feature(name) as Lang.Boolean {
        var features = layout()["features"];
        if (features == null) {
            return true;
        }
        var value = (features as Lang.Dictionary)[name];
        return value == null ? true : value as Lang.Boolean;
    }

    //! Přepočítá měřítko podle skutečné velikosti displeje.
    function prepare(dc) as Void {
        prepareSize(dc.getWidth(), dc.getHeight());
    }

    //! Totéž bez kreslicího kontextu - mapové view potřebuje rozměry okna už
    //! v konstruktoru, kde žádné dc není.
    function prepareSize(width, height) as Void {
        var canvas = section("canvas");
        mScaleX = width / (canvas["width"] as Lang.Number).toFloat();
        mScaleY = height / (canvas["height"] as Lang.Number).toFloat();
        mScale = mScaleX < mScaleY ? mScaleX : mScaleY;
    }

    //! Okno mapy v pixelech displeje jako [vlevo, nahoře, vpravo, dole].
    //! Je o kousek menší než rámeček, aby kartografie nelezla pod okraj.
    function mapRect() as Lang.Array {
        var margin = number("middle", "margin");
        var side = number("middle", "sideWidth");
        var gap = number("middle", "gap");
        var inset = number("map", "focusInset");
        var left = margin + side + gap + inset;

        return [
            x(left).toNumber(),
            y(number("middle", "top") + inset).toNumber(),
            x(number("canvas", "width") - left).toNumber(),
            y(number("middle", "bottom") - inset).toNumber()
        ];
    }

    //! Ve stylu přístrojového štítu je mapa přes celou obrazovku a zaostřuje se
    //! na pruh mezi horním a spodním překryvem.
    function cockpitMapRect() as Lang.Array {
        var focus = group("cockpit", "focus");
        return [
            0,
            y(at(focus, "top")).toNumber(),
            x(number("canvas", "width")).toNumber() - 1,
            y(at(focus, "bottom")).toNumber()
        ];
    }

    function x(designX) {
        return designX * mScaleX;
    }

    function y(designY) {
        return designY * mScaleY;
    }

    //! Pro poloměry a tloušťky, kde by nerovnoměrné měřítko rozbilo tvar.
    function s(designSize) {
        return designSize * mScale;
    }

    //: Systémové fonty od nejmenšího po největší. Drží se v proměnné, protože
    //: kreslení běží každou vteřinu a pole by se jinak vyrábělo pořád dokola.
    var mTextFonts = null;
    var mNumberFonts = null;

    function textFonts() as Lang.Array {
        if (mTextFonts == null) {
            mTextFonts = [
                Graphics.FONT_XTINY,
                Graphics.FONT_TINY,
                Graphics.FONT_SMALL,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_LARGE
            ];
        }
        return mTextFonts as Lang.Array;
    }

    //! Číslicové fonty jsou vyšší a užší - pro tachometr a hodnoty v buňkách.
    function numberFonts() as Lang.Array {
        if (mNumberFonts == null) {
            mNumberFonts = [
                Graphics.FONT_XTINY,
                Graphics.FONT_TINY,
                Graphics.FONT_NUMBER_MILD,
                Graphics.FONT_NUMBER_MEDIUM,
                Graphics.FONT_NUMBER_HOT,
                Graphics.FONT_NUMBER_THAI_HOT
            ];
        }
        return mNumberFonts as Lang.Array;
    }

    function pick(dc, candidates as Lang.Array, designSize) {
        var target = designSize * mScale * FONT_HEIGHT_RATIO;
        var best = candidates[0];
        for (var i = 0; i < candidates.size(); i += 1) {
            var candidate = candidates[i];
            if (dc.getFontHeight(candidate) <= target) {
                best = candidate;
            }
        }
        return best;
    }

    //! Největší z `candidates`, do kterého se text vejde na `maxWidth` pixelů.
    //!
    //! Návrh počítá s popiskami kolem deseti pixelů, jenže nejmenší Garmin font
    //! je na Edge 1050 vysoký 21 pixelů - textFont() proto vrací něco výrazně
    //! většího, než si rozvržení představuje, a sousední údaje se překrývají.
    //! Pod XTINY se ale zmenšit nedá; tam už si musí pomoct samo rozvržení.
    function shrink(dc, candidates as Lang.Array, font, text, maxWidth) {
        var index = 0;
        for (var i = 0; i < candidates.size(); i += 1) {
            if (candidates[i] == font) {
                index = i;
            }
        }
        while (index > 0 && dc.getTextWidthInPixels(text, font) > maxWidth) {
            index -= 1;
            font = candidates[index];
        }
        return font;
    }

    function fitFont(dc, text, maxWidth, designSize) {
        return shrink(dc, textFonts(), textFont(dc, designSize), text, maxWidth);
    }

    function fitNumberFont(dc, text, maxWidth, designSize) {
        return shrink(dc, numberFonts(), numberFont(dc, designSize), text, maxWidth);
    }

    //! Nejbližší menší systémový font pro text dané návrhové velikosti.
    function textFont(dc, designSize) {
        return pick(dc, textFonts(), designSize);
    }

    function numberFont(dc, designSize) {
        return pick(dc, numberFonts(), designSize);
    }
}
