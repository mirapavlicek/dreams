# Garmin Connect IQ

Dvě aplikace a společné vývojové prostředí:

- **[RideDashboard](#ridedashboard--palubovka-pro-edge-1050)** — palubovka pro
  cyklopočítač Edge 1050 (480×800) ve stylu přístrojového štítu auta: mapa
  přístroje pod celou obrazovkou, nad ní tachometr, kadence, dojezd e-biku,
  převýšení a počasí.
- **[QMailDashboard](#qmaildashboard--stav-schránky-na-hodinkách)** — stav
  poštovní schránky jako hustota pravděpodobnosti `|ψ|²` podle knihovny `qmail`.

---

# RideDashboard — palubovka pro Edge 1050

Dva styly, přepínají se v nastavení aplikace.

## Styl „přístrojový štít“ (výchozí)

![Palubovka ve stylu přístrojového štítu](docs/preview/ride-cockpit.png)

Mapa vyplňuje celou obrazovku a přes ni jsou dva překryvy jako v přístrojovém
štítu auta — nahoře kompasová páska, tříčtvrteční budík kadence, digitální
tachometr s desetinným místem v akcentu, hodiny a pilulky s průměrnou
a maximální rychlostí; dole dojezd e-biku, vzdálenost do cíle s odhadem
příjezdu, najeté kilometry a řádek se stavem baterie, převýšením a počasím.
V rohu mapy je náhled celé projeté trasy, aby byl vidět tvar jízdy i při
zazoomované mapě, a spodní hranu displeje lemuje tenký proužek baterie.

Překryvy nemají tvrdou hranu: směrem k mapě se rozplývají do ztracena. Kreslí
se jako plná výplň a pár desítek pruhů s klesající alfou přes
`Graphics.createColor()` (API 4.0 a výš). Na starších jednotkách zůstane
neprůhledný pruh, jinak se nezmění nic.

## Styl „panely“

![Palubovka s panely](docs/preview/ride-edge1050-map.png)

Rozvržení shora dolů:

| Pásmo | Obsah |
|---|---|
| Horní lišta | hodiny, stav GPS, baterie jednotky |
| Půlkruh 0–200 | kadence; barva se mění podle pásma (pod 50 šedá, do 100 zelená, do 150 oranžová, výš červená) |
| Střed půlkruhu | digitální tachometr, desetinné místo menším písmem |
| Pod rychlostí | průměrná a maximální rychlost |
| Prostřední pás | mapa uprostřed, po stranách kompas a dojezd na elektřinu (vlevo), vzdálenost do cíle a najeté kilometry (vpravo) |
| Spodní lišta | zbývající energie e-biku, nastoupáno, sestoupáno, teplota a počasí |

## Jak se mapa dostane do vlastního rozvržení

V obou stylech je to **opravdová mapa z paměti přístroje**, ne jen nakreslená
stopa. Trik je v tom, že `setScreenVisibleArea()` mapu neořízne. Mapa se vykreslí pod
celou obrazovkou a metoda jen říká, na kterou část se má zaostřit a co ještě
není zakryté rozhraním aplikace — přesně jak to popisuje vlákno
[MapView](https://forums.garmin.com/developer/connect-iq/f/discussion/7014/mapview)
na fóru Connect IQ. Okolí mapového okna si tedy aplikace musí přebarvit sama,
jinak kartografie prosvítá pod ciferníky.

Prakticky to znamená:

- `RideMapView` dědí z `MapTrackView`, takže se mapa sama drží aktuální polohy
  a kreslí navigační šipku; projetá stopa jde nad ni jako `MapPolyline`.
- Kreslení nesmí v mapovém režimu zavolat `dc.clear()`, ten by mapu přetřel.
  `RideChrome` proto vyplní jen čtyři pruhy kolem okna a `RideCockpit` jen dva
  překryvy nahoře a dole.
- Mapové view nejde vrátit z `getInitialView()`, dá se jen vystrčit přes
  `pushView()`. Výchozí obrazovka je proto `RideView` a mapa se otevře hned po
  startu.
- **Výběr** přepne mapu přes celou obrazovku (`MAP_MODE_BROWSE`, posouvání
  a zoom jako v nativní mapě), **zpět** vrátí palubovku a podruhé odejde na
  variantu s drobečkovou stopou.
- Bez map v paměti (`WatchUi has :MapTrackView`) nebo po vypnutí volby *Mapa
  z paměti přístroje* zůstane drobečková stopa z GPS bodů. Pozor při přidávání
  jednotek bez kartografie do manifestu — třída dědící z `MapTrackView` se pro
  ně nepřeloží, musela by se vyřadit anotací v `monkey.jungle`.

## Dojezd elektrokola: měření místo odhadu

Edge dojezd e-biku ukazuje sám, ale Connect IQ na něj hotovou třídu nemá —
`Toybox.AntPlus` zná pulsy, výkon i řazení, profil elektrokol (LEV) v něm
chybí. Dá se ale obejít: `RideLev` si otevře **generický ANT kanál** na device
type 20 (frekvence 57, perioda 8192 = 4 Hz) a datové stránky si rozebere sám.

| Stránka | Co z ní bereme |
|---|---|
| 1 | stupeň asistence, rychlost kola |
| 2 | **dojezd v km** (12 bitů, nula = kolo neví), odometr |
| 3 | stav baterie v procentech, varování o vybití, % asistence |
| 4 | spotřeba ve Wh/km, kilometry od posledního nabití |
| 34 | náhrada stránky 2 — místo dojezdu posílá spotřebu |

Kanál je jen poslouchající (`CHANNEL_TYPE_RX_ONLY`) — Giant RideControl jiný typ
kanálu nepřijme a zároveň tím kolu nic neposíláme.

Dojezd, baterie i spotřeba fungují na **jakémkoli kole s profilem LEV** — to je
standard, ne značková věc. Značkové jsou jen názvy režimů asistence: profil
posílá pouhé číslo stupně 0–7 a Garmin ho proto nativně ukazuje jen jako číslo
nebo sloupečky. Ze společné stránky 80 se ale dá přečíst **výrobce** (číselník
je stejný jako ve FIT), takže stupeň jde pojmenovat tak, jak svítí na kole:

| Výrobce (ID) | Režimy | Poznámka |
|---|---|---|
| Giant (108) | ECO, BASIC, ACTIVE, AUTO, SPORT, POWER | ověřené rozprostření po stupních 0–7 |
| Specialized (63), Mahle (299) | ECO, TRAIL, TURBO | ověřené |
| Yamaha (304) | ECO+, ECO, STD, HIGH, EXPW | ověřené |
| Fazua (318) | BREEZE, RIVER, ROCKET | jen když kolo hlásí tři stupně |
| TQ (141) | ECO, MID, HIGH | jen když kolo hlásí tři stupně |

U prvních tří značek je ověřené i to, jak se jejich režimy rozprostřou po sedmi
stupních profilu (kola s méně režimy stupně zdvojují). U Fazuy a TQ známe jen
pořadí režimů, takže je aplikace pojmenuje jen tehdy, když kolo na stránce 5
hlásí přesně tolik stupňů, kolik jich značka má — pak je mapování jedna ku jedné
a není co odhadovat. Jinak zůstane `ASIST 3/5`, tedy stupeň a počet režimů z kola.
Vymyslet si jméno je horší než ho neukázat.

Po prvním spárování se ANT+ ID kola uloží do nastavení, aby se kanál příště
nechytil cizího kola, které jede kolem. Vynulováním pole se aplikace spáruje
znovu.

Dojezd se bere v tomto pořadí:

1. **přímo z kola** (stránka 2) — totéž číslo, co ukazuje Edge, kolo v něm má
   vlastní spotřebu i nastavenou asistenci,
2. **ze stavu baterie** — když kolo dojezd neposílá, spočítá se z procent
   a spotřeby ve Wh/km podle kapacity vyplněné v nastavení; bez kapacity
   z poměrné části dojezdu na plnou,
3. **odhad z ujetých kilometrů** — když se s kolem nemluví vůbec.

Odhad se v palubovce přizná: v přístrojovém štítu jednotkou `km · odhad`
a popiskem `E-BIKE · ODHAD`, v panelech poznámkou pod hodnotou. Měřený dojezd
naopak ukazuje i režim asistence (`E-BIKE · ACTIVE`).

![Dojezd jako odhad, když kolo LEV neumí](docs/preview/ride-cockpit-estimate.png)

Profil LEV vysílá Giant (RideControl), Specialized, Yamaha, Mahle, Fazua Ride 60
(od firmware bundle 007) a TQ HPR50 v Treku Fuel EXe. **Bosch** ANT+ ignoruje
úplně a **Shimano STEPS** jede po Bluetooth, tam zůstane odhad. Ne každý systém
posílá všechno — TQ třeba dojezd nehlásí, takže se počítá ze stavu baterie.

**Pozor na nativní spárování:** na jednom kole může viset jen jeden posluchač.
Když je e-bike připojený přes systémové menu *Senzory* nebo ho drží jiná
Connect IQ aplikace, náš kanál data nedostane a dojezd spadne na odhad — kolo
je pak potřeba ze *Senzorů* odpojit. Data se objeví do zhruba patnácti vteřin
od chvíle, kdy je Edge blízko ovladače kola.

Rozvržení je popsané v `RideDashboard/resources/json/layout.json` v pixelech
návrhového plátna 480×800; při kreslení se přepočítá na skutečný displej, takže
stejná čísla platí i pro menší jednotky Edge.

```bash
python3 garmin/tools/preview_ride.py --cockpit --map    # přístrojový štít
python3 garmin/tools/preview_ride.py --map              # panely s mapou
python3 garmin/tools/preview_ride.py                    # panely bez mapy
python3 garmin/tools/preview_ride.py --cockpit --map --estimate  # kolo bez LEV
./garmin/check.sh RideDashboard                         # překlad bez Garmin účtu
./garmin/run_simulator.sh edge1050 RideDashboard
```

V náhledu s `--map` je kartografie jen ilustrace toho, co na přístroji vykreslí
`MapTrackView` — renderer žádné mapové podklady nemá.

---

# QMailDashboard — stav schránky na hodinkách

Hodinková aplikace, která ukazuje stav schránky tak, jak ho počítá `qmail`:
ne jako „máš 3 spamy“, ale jako **hustotu pravděpodobnosti `|ψ|²`** přes
verdikty *legitimní / spam / phishing*. Obvod displeje je celý pravděpodobnostní
prostor, střed je kolaps měřením a proužek dole je neurčitost (entropie), tedy
kolik pošty si zaslouží ruční pohled.

![Stavy schránky](docs/preview/scenarios.png)

Zleva: čistá schránka, převaha spamu, jasný phishing a stav, kdy je vlnová
funkce rozprostřená skoro rovnoměrně — právě tehdy má smysl kontrolovat ručně.

## Co je v aplikaci

| Prvek | Význam |
|---|---|
| Barevný prstenec | `\|ψ\|²` jednotlivých verdiktů; délka oblouku = pravděpodobnost |
| Text ve středu | kolaps (`argmax \|ψ\|²`) a jeho jistota |
| Modrý proužek | normalizovaná entropie — jak je stav „rozmazaný“ |
| Patička | kolik e-mailů čeká na ruční kontrolu z celkového počtu měření |
| Glance | tentýž stav na jeden řádek v seznamu aplikací |

![Glance](docs/preview/glance.png)

Rozvržení se počítá z rozměrů displeje, takže sedí na kulaté i hranaté panely:

![Zařízení](docs/preview/devices.png)

## Struktura

```
garmin/
  QMailDashboard/
    manifest.xml                     # seznam zařízení, oprávnění, minApiLevel
    monkey.jungle                    # build konfigurace
    resources/json/theme.json        # barvy a geometrie – jediný zdroj pravdy
    resources/settings/              # adresa endpointu, interval obnovy
    source/QMailApp.mc               # vstupní bod aplikace + glance
    source/QMailModel.mc             # data: web request nebo demo hodnoty
    source/DashboardView.mc          # kreslení prstence a středu
    source/GlanceView.mc             # kompaktní řádek
  RideDashboard/
    resources/json/layout.json       # rozvržení palubovky v pixelech 480x800
    resources/settings/              # elektrokolo, dojezd, počasí, mapa, styl
    source/RideApp.mc                # vstupní bod + odběr GPS pozic
    source/RideLayout.mc             # škálování návrhu na displej, výběr fontů
    source/RideData.mc               # metriky z Activity, Weather a Position
    source/RideLev.mc                # elektrokolo přes ANT+ profil LEV
    source/RideChrome.mc             # kreslení stylu s panely
    source/RideCockpit.mc            # kreslení stylu přístrojového štítu
    source/RideView.mc               # obrazovka s drobečkovou stopou
    source/RideMapView.mc            # obrazovka s mapou z paměti přístroje
  tools/preview.py                   # náhled qmail dashboardu do PNG
  tools/preview_ride.py              # náhled palubovky do PNG
  tools/qmail_server.py              # servíruje reálná data z .eml složky
  tools/make_icon.py                 # launcher ikona z barev tématu
  tools/sync_devices.py              # srovná manifest se staženými zařízeními
  tools/stub_device.py               # náhradní definice zařízení pro překlad
  setup_dev_env.sh                   # instalace SDK, závislostí a klíče
  check.sh                           # překlad bez Garmin účtu (syntaxe a typy)
  build.sh / run_simulator.sh        # překlad a spuštění v simulátoru
```

Konfigurační JSON (`theme.json`, `layout.json`) čte jak hodinková aplikace
(`Rez.JsonData`), tak náhledový renderer — barvy i rozvržení se tak mění na
jednom místě.

## Instalace prostředí

```bash
./garmin/setup_dev_env.sh          # SDK, běhové závislosti simulátoru, klíč
source ~/connectiq/env.sh          # monkeyc, monkeydo, simulator v PATH
```

Skript stáhne Connect IQ SDK pro Linux, doplní knihovny, které simulátor
potřebuje (je slinkovaný proti `webkit2gtk-4.0`, který v Ubuntu 24.04 chybí),
vygeneruje podepisovací klíč a nainstaluje headless
[connect-iq-sdk-manager](https://github.com/lindell/connect-iq-sdk-manager-cli).

### Device packy vyžadují Garmin účet

Definice zařízení a fonty pro simulátor Garmin nepublikuje volně — endpoint
`api.gcs.garmin.com/ciq-product-onboarding/devices` vrací bez přihlášení `401`
a GUI SDK Manager taky začíná loginem. Bez nich `monkeyc -d <zařízení>` skončí
na `Invalid device id` a simulátor nemá co zobrazit.

```bash
export GARMIN_USERNAME="..."       # účet z developer.garmin.com
export GARMIN_PASSWORD="..."
connect-iq-sdk-manager agreement accept
connect-iq-sdk-manager login
connect-iq-sdk-manager device download --manifest garmin/QMailDashboard/manifest.xml --include-fonts
python3 garmin/tools/sync_devices.py    # srovná manifest se staženým
```

## Kontrola překladu bez Garmin účtu

`monkeyc` vyžaduje cílové zařízení, ale ke kontrole syntaxe a typů stačí
vlastnoručně napsaný `compiler.json` — žádný stažený device pack:

```bash
./garmin/check.sh                     # oba projekty
./garmin/check.sh RideDashboard       # jen jeden
./garmin/check.sh RideDashboard -l 2  # ukecanější typová analýza
```

Skript si vyrobí náhradní zařízení (`qmailstub` 454×454 kulaté, `ridestub`
480×800 hranaté) a přeloží proti němu dočasnou kopii projektu. Na spuštění
v simulátoru to nestačí — ten navíc potřebuje Garmin fonty — ale odhalí to
všechno, co odmítne překladač.

## Překlad a spuštění

```bash
./garmin/build.sh fenix847mm                       # -> QMailDashboard/bin/*.prg
./garmin/build.sh edge1050 RideDashboard
./garmin/run_simulator.sh edge1050 RideDashboard   # překlad + simulátor
```

Na stroji bez obrazovky si nejdřív pusť X server:

```bash
Xvfb :1 -screen 0 1280x1024x24 & export DISPLAY=:1
```

## Náhled bez simulátoru

Dokud device packy nejsou k dispozici, vykreslí stejnou obrazovku renderer
v Pythonu. Používá `theme.json` a opakuje postup z `DashboardView.mc`, takže
změna barev nebo rozvržení je vidět hned:

```bash
python3 garmin/tools/preview.py --all                       # vše do garmin/docs/preview
python3 garmin/tools/preview.py --device venu3 --scenario spam
python3 garmin/tools/preview.py --json http://localhost:8720/qmail.json
```

Je to náhled, ne snímek ze simulátoru — písma jsou nahrazená DejaVu, takže
metriky textu se od Garmin fontů o pár pixelů liší.

## Reálná data z qmailu

Aplikace umí číst JSON z adresy vyplněné v nastavení (Connect IQ Mobile nebo
pole *Settings* v simulátoru). Endpoint dodá `tools/qmail_server.py`, který
prožene složku s `.eml` knihovnou `qmail` a složí z výsledků jedno rozdělení
pro celou schránku:

```bash
python3 garmin/tools/qmail_server.py --mail-dir examples --port 8720
python3 garmin/tools/qmail_server.py --once      # jen vypsat JSON
```

```json
{
  "verdict": "phishing",
  "probabilities": { "ham": 0.011, "spam": 0.027, "phishing": 0.963 },
  "confidence": 0.963,
  "uncertainty": 0.165,
  "needs_review": 3,
  "scanned": 128
}
```

Bez vyplněné adresy aplikace ukazuje demo hodnoty odpovídající rozboru
`examples/phishing.eml` a v titulku má `qmail · demo`.
