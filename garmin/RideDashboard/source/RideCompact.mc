using Toybox.Lang;

//! Rozpozná, jestli má kreslení k dispozici celý displej, nebo jen pruh.
//!
//! Datové pole nedostane vždycky celou obrazovku - typicky je to pruh nad nebo
//! pod nativní mapou. Celá palubovka by se do něj jen svisle zmáčkla, takže se
//! místo ní kreslí jen ten překryv původního návrhu, který do pruhu patří
//! (viz RideCockpit.drawTopBand a drawBottomBand).
module RideCompact {

    //! Rozhoduje poměr stran proti návrhovému plátnu: když je rámeček výrazně
    //! plošší, je to podíl na datové obrazovce, ne celý displej.
    function band(dc) as Lang.Boolean {
        var canvas = RideLayout.section("canvas");
        var designed = (canvas["height"] as Lang.Number).toFloat() /
            (canvas["width"] as Lang.Number).toFloat();
        var actual = dc.getHeight().toFloat() / dc.getWidth().toFloat();
        return actual < designed * 0.75;
    }
}
