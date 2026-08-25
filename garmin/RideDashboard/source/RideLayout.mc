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

    function number(sectionName, key) {
        return (section(sectionName)[key] as Lang.Number).toFloat();
    }

    function color(name) {
        return section("colors")[name];
    }

    //! Přepočítá měřítko podle skutečné velikosti displeje.
    function prepare(dc) as Void {
        var canvas = section("canvas");
        mScaleX = dc.getWidth() / (canvas["width"] as Lang.Number).toFloat();
        mScaleY = dc.getHeight() / (canvas["height"] as Lang.Number).toFloat();
        mScale = mScaleX < mScaleY ? mScaleX : mScaleY;
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

    //! Nejbližší menší systémový font pro text dané návrhové velikosti.
    function textFont(dc, designSize) {
        return pick(dc, [
            Graphics.FONT_XTINY,
            Graphics.FONT_TINY,
            Graphics.FONT_SMALL,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_LARGE
        ], designSize);
    }

    //! Číslicové fonty jsou vyšší a užší - pro tachometr a hodnoty v buňkách.
    function numberFont(dc, designSize) {
        return pick(dc, [
            Graphics.FONT_XTINY,
            Graphics.FONT_TINY,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_THAI_HOT
        ], designSize);
    }
}
