using Toybox.Graphics;
using Toybox.Lang;

//! Záchranná síť pro chyby, které se projeví až na přístroji.
//!
//! Ručně nahraná aplikace nemá kam vypsat log a `CIQ_LOG.YML` na přístroji
//! zůstává bez zásobníku, dokud si k němu uživatel nezkopíruje ladicí symboly.
//! Když tedy kreslení spadne, je lepší chybu vypsat rovnou na displej: jedna
//! fotka pak řekne víc než hodina hádání.
//!
//! Zachytávat výjimky kolem kreslení není hezké a v běžné aplikaci by to bylo
//! zakrývání problémů. Tady je to schválně - palubovka běží na firmwaru, na
//! který nemáme jak dosáhnout, a přijít o obrazovku je horší než ji mít
//! s poznámkou.
module RideTrouble {

    //: Poslední zachycená chyba; kreslí se, dokud ji nepřebije jiná.
    var mMessage as Lang.String or Null = null;
    var mWhere as Lang.String = "";

    function note(where as Lang.String, exception) as Void {
        mWhere = where;
        var message = null;
        try {
            message = exception.getErrorMessage();
        } catch (inner) {
            // I getErrorMessage() může selhat; pak zbude aspoň místo činu.
        }
        mMessage = message == null ? "bez popisu" : message;
    }

    function caught() as Lang.Boolean {
        return mMessage != null;
    }

    //! Vykreslí chybu přes celou plochu. Používá jen holé dc, žádné rozvržení
    //! ani fonty z layoutu - to všechno mohlo být příčinou pádu.
    function draw(dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var font = Graphics.FONT_XTINY;
        var height = dc.getFontHeight(font);
        var y = dc.getHeight() / 2 - height * 2;

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y, font, "CHYBA PALUBOVKY",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width / 2, y + height, font, mWhere,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var message = mMessage as Lang.String;
        var line = "";
        var row = 2;
        // Zpráva se láme po slovech, ať se vejde na úzký displej.
        var words = message.substring(0, message.length()) + " ";
        var start = 0;
        for (var i = 0; i < words.length(); i += 1) {
            if (!words.substring(i, i + 1).equals(" ")) {
                continue;
            }
            var word = words.substring(start, i);
            start = i + 1;
            var candidate = line.length() == 0 ? word : line + " " + word;
            if (dc.getTextWidthInPixels(candidate, font) > width - 8 && line.length() > 0) {
                dc.drawText(width / 2, y + height * row, font, line,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                row += 1;
                line = word;
            } else {
                line = candidate;
            }
        }
        if (line.length() > 0) {
            dc.drawText(width / 2, y + height * row, font, line,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
