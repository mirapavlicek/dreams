"""qmail - kvantově inspirovaná kontrola e-mailů proti phishingu a spamu.

Analogie: pozice elektronu není pevná hodnota, ale je popsána vlnovou
funkcí psi(x). Pravděpodobnost nalezení elektronu v bode x je |psi(x)|^2
a teprve *mereni* vlnovou funkci "zhroutí" (kolaps) do konkrétního výsledku.

Stejně tak zde e-mail není apriori "spam" nebo "ham". Je v *superpozici*
základních stavů (legitimní / spam / phishing). Jednotlivé signály
(podezřelé odkazy, naléhavý jazyk, neshoda odesílatele, výsledky SPF/DKIM)
přispívají *komplexními amplitudami* do stavového vektoru. Amplitudy se
mohou sčítat konstruktivně i destruktivně (interference) - např. úspěšná
autentizace dokáže "vyrušit" část phishingové amplitudy. Pravděpodobnost
každého verdiktu pak je |amplituda|^2 a finální rozhodnutí je *kolaps*
této superpozice.
"""

from .states import Verdict
from .quantum import QuantumState
from .signals import Signal
from .screen import ScreenResult, screen_email, screen_raw

__all__ = [
    "Verdict",
    "QuantumState",
    "Signal",
    "ScreenResult",
    "screen_email",
    "screen_raw",
]

__version__ = "0.1.0"
