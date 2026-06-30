# qmail — kvantově inspirovaná kontrola e-mailů proti phishingu a spamu

> Verdikt o e-mailu se neurčuje binárně, ale jako **hustota pravděpodobnosti
> `|ψ|²`** přes možné stavy — stejně jako se poloha elektronu nezjišťuje jako
> pevné číslo, ale jako pravděpodobnost daná vlnovou funkcí, kterou teprve
> *měření* zhroutí (kolaps) do konkrétní hodnoty.

`qmail` je malý nástroj a knihovna v čistém Pythonu (jen standardní knihovna,
žádné závislosti), který tuto fyzikální analogii používá jako model pro
klasifikaci e-mailů.

## Myšlenka: od polohy elektronu k verdiktu o e-mailu

V kvantové mechanice neříkáme „elektron je v bodě *x*". Stav popisuje vlnová
funkce `ψ` a měřitelná veličina (poloha) má **rozdělení pravděpodobnosti**
`|ψ(x)|²` (Bornovo pravidlo). Teprve měřením se superpozice „zhroutí" do
jednoho výsledku.

`qmail` mapuje tento princip na rozhodování o e-mailu:

| Kvantový jev | Protějšek v `qmail` |
|---|---|
| Bázové stavy (vlastní stavy operátoru) | verdikty `ham` / `spam` / `phishing` |
| Vlnová funkce `ψ` | komplexní stavový vektor `QuantumState` |
| Příspěvky / poruchy hamiltoniánu | signály z detektorů (komplexní amplitudy) |
| Interference vln | sčítání amplitud (fáze 0 zesiluje, fáze π ruší) |
| Hustota pravděpodobnosti `|ψ(x)|²` | `probabilities()` jednotlivých verdiktů |
| Měření / kolaps | `collapse()` → finální verdikt (argmax `|ψ|²`) |
| Neurčitost polohy | entropie rozdělení (jak je stav „rozmazaný") |
| Opakované měření (více „shots") | `sample_distribution()` (Monte Carlo) |

Klíčové vlastnosti modelu:

- **Žádný signál není absolutní.** Každý jen přispívá amplitudou; výsledek
  vzniká až superpozicí všech příspěvků a následným kolapsem.
- **Interference.** Příspěvky se sčítají v amplitudovém prostoru, takže se
  mohou zesilovat i potlačovat.
- **Útlum místo přestřelení.** Silně „ospravedlňující" jev (úspěšná
  autentizace SPF/DKIM/DMARC) phishingovou/spamovou amplitudu *multiplikativně
  utlumí* — destruktivní vliv, který ale nikdy nepřeklopí stav do velké
  záporné amplitudy.
- **Neurčitost = signál k lidské kontrole.** Když je vlnová funkce
  rozprostřená přes více verdiktů (vysoká entropie), stav „není dost
  lokalizovaný" a `needs_review` doporučí ruční posouzení — analogie toho, že
  polohu nelze ostře určit, dokud je `ψ` rozmazaná.

## Instalace

Není potřeba nic instalovat (kromě Pythonu ≥ 3.10). Volitelně jako balíček:

```bash
pip install -e .
```

## Použití (CLI)

```bash
# rozbor .eml souboru
python -m qmail examples/phishing.eml

# čtení ze stdin
cat examples/spam.eml | python -m qmail

# strojově čitelný výstup
python -m qmail --json examples/phishing.eml

# opakované "měření" (Monte Carlo kolaps podle |psi|^2)
python -m qmail --shots 1000 examples/spam.eml
```

Příklad výstupu:

```
Hustota pravděpodobnosti verdiktů:
  legitimní   |------------------------|   1.1%
  spam        |#-----------------------|   2.7%
  phishing    |#######################-|  96.3%

Kolaps (verdikt):   PHISHING
Důvěra (špička):    96.3%
Neurčitost (entrop.): 0.165  (0=jisté, 1=zcela rozmazané)
```

Návratový kód: `0` pro `ham`, `2` pro spam/phishing (vhodné pro skripty).

## Použití (knihovna)

```python
from qmail import screen_raw

raw = open("examples/phishing.eml", "rb").read()
result = screen_raw(raw)

print(result.verdict)            # Verdict.PHISHING
print(result.probabilities)      # {HAM: 0.011, SPAM: 0.027, PHISHING: 0.963}
print(result.confidence)         # 0.963
print(result.uncertainty)        # 0.165  (normalizovaná entropie)
print(result.needs_review)       # False

# pravděpodobnostní měření (kolaps podle |psi|^2)
print(result.measure())          # Verdict.PHISHING (s pravděp. 0.963)
print(result.sample_distribution(shots=1000))
```

## Architektura

```
qmail/
  states.py     # bázové stavy (HAM / SPAM / PHISHING)
  quantum.py    # QuantumState: amplitudy, |psi|^2, kolaps, entropie, útlum
  signals.py    # Signal: komplexní amplitudové příspěvky + útlum
  parser.py     # rozbor surového .eml (jen stdlib email/html)
  detectors.py  # heuristiky -> signály (odkazy, odesílatel, jazyk, autentizace…)
  screen.py     # prior -> aplikace signálů -> ScreenResult
  cli.py        # příkazová řádka
```

Tok zpracování:

1. `prior` — výchozí vlnová funkce blízko stavu `|ham⟩` (s nenulovou baseline).
2. Detektory vyrobí **signály** (komplexní amplitudy / útlumové faktory).
3. Amplitudy se **sečtou** do stavu (interference), pak se aplikuje **útlum**.
4. Stav se **normalizuje** → `|ψ|²` dá pravděpodobnosti verdiktů.
5. **Kolaps** (`argmax |ψ|²`) určí verdikt; entropie udá neurčitost.

## Detekované signály (výběr)

- **Autentizace** — SPF/DKIM/DMARC pass (tlumí hrozbu) i fail (posiluje phishing).
- **Identita odesílatele** — neshoda `From` / `Reply-To` / `Return-Path`,
  spoofing zobrazovaného jména (značka v názvu vs. freemail doména).
- **Odkazy** — IP místo domény, punycode/homografy, zkracovače, `@` v URL,
  mnoho subdomén, neshoda viditelného textu a cíle, mnoho cílových domén.
- **Jazyk** — naléhavost/nátlak, žádost o přihlašovací údaje, reklamní/podvodné
  fráze; kombinace naléhavosti + žádosti o údaje (klasický phishing).
- **Formátování** — KŘIK velkými písmeny, mnoho vykřičníků, HTML bez textu.
- **Přílohy** — spustitelné/skriptové přípony, archivy.

Detektory rozumí anglickým i (přepsaným) českým výrazům.

## Testy

```bash
pip install pytest
python -m pytest
```

## Poznámka

Jde o **koncepční, kvantově *inspirovaný*** model — neběží na kvantovém
počítači a nenahrazuje produkční antispam. Demonstruje, jak lze rozhodování
o e-mailu formulovat pravděpodobnostně po vzoru určování polohy elektronu:
přes amplitudy, interferenci, `|ψ|²` a kolaps měřením.
