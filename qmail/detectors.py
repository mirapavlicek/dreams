"""Detektory jevů. Každý vrací seznam signálů s amplitudovými příspěvky.

Filozofie vah: prior začíná silně v |ham>. Detektory přidávají amplitudu do
spamu/phishingu (fáze 0) nebo ji díky opačné fázi (pi) ubírají - to je princip
interference. Žádný jednotlivý signál není absolutní; teprve jejich superpozice
a následný kolaps určí verdikt, podobně jako se poloha elektronu vyjeví až
měřením hustoty |psi|^2.
"""

from __future__ import annotations

import re
from typing import Callable

from .parser import ParsedEmail
from .signals import Signal, amp, make_signal

# Známé značky často zneužívané k display-name spoofingu.
_BRANDS = (
    "paypal", "apple", "microsoft", "google", "amazon", "netflix",
    "facebook", "instagram", "bank", "banka", "csob", "kb", "raiffeisen",
    "moneta", "fio", "alza", "dhl", "fedex", "ups", "ceska posta",
    "ceska sporitelna", "sporitelna", "office365", "outlook", "icloud",
)

_FREEMAIL = (
    "gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "seznam.cz",
    "centrum.cz", "email.cz", "proton.me", "protonmail.com", "icloud.com",
    "post.cz", "atlas.cz",
)

_SHORTENERS = (
    "bit.ly", "tinyurl.com", "goo.gl", "t.co", "ow.ly", "is.gd",
    "buff.ly", "cutt.ly", "rebrand.ly", "shorturl.at",
)

_URGENCY = (
    "urgent", "immediately", "act now", "as soon as possible", "asap",
    "final notice", "last warning", "account suspended", "suspended",
    "verify your account", "verify now", "confirm your account",
    "limited time", "expires", "within 24 hours", "your account will be",
    "okamzite", "ihned", "naléhavé", "naléhave", "ucet byl zablokovan",
    "ucet bude zablokovan", "overte sve udaje", "overte ucet", "potvrdte",
    "do 24 hodin", "posledni vyzva", "vase platba",
)

_CREDENTIAL = (
    "password", "passwords", "login", "log in", "sign in", "username",
    "credit card", "card number", "cvv", "pin", "social security",
    "verify your identity", "confirm your identity", "update your payment",
    "billing information", "heslo", "prihlaseni", "cislo karty",
    "rodne cislo", "overeni totoznosti", "platebni udaje",
)

_MONEY_SPAM = (
    "congratulations", "you have won", "winner", "lottery", "prize",
    "free", "100% free", "risk free", "guarantee", "guaranteed",
    "click here", "buy now", "order now", "discount", "cheap", "viagra",
    "casino", "bitcoin", "crypto", "investment opportunity", "earn money",
    "make money", "work from home", "vyhra", "vyhrali jste", "zdarma",
    "sleva", "investice", "kliknete zde", "nakupte", "loterie",
)

_RISKY_EXT = (
    ".exe", ".scr", ".js", ".jar", ".vbs", ".bat", ".cmd", ".com",
    ".pif", ".html", ".htm", ".iso", ".lnk", ".docm", ".xlsm",
)

_IP_HOST_RE = re.compile(r"^\d{1,3}(?:\.\d{1,3}){3}$")

Detector = Callable[[ParsedEmail], list[Signal]]


def _normtext(s: str) -> str:
    return re.sub(r"\s+", " ", s.lower())


def _count_hits(text: str, needles) -> list[str]:
    return [n for n in needles if n in text]


# -- jednotlivé detektory -------------------------------------------------


def detect_authentication(mail: ParsedEmail) -> list[Signal]:
    """SPF/DKIM/DMARC: úspěch silně podporuje ham a interferenčně ruší phishing."""
    blob = _normtext(f"{mail.auth_results} {mail.received_spf}")
    if not blob.strip():
        return []
    signals: list[Signal] = []

    spf_pass = "spf=pass" in blob or blob.strip().startswith("pass")
    dkim_pass = "dkim=pass" in blob
    dmarc_pass = "dmarc=pass" in blob
    spf_fail = "spf=fail" in blob or "spf=softfail" in blob
    dkim_fail = "dkim=fail" in blob
    dmarc_fail = "dmarc=fail" in blob

    if dmarc_pass or (spf_pass and dkim_pass):
        # Silná autentizace: posílí |ham> a destruktivně utlumí phishing/spam.
        signals.append(make_signal(
            "auth_pass",
            "Prošla autentizace (SPF/DKIM/DMARC) - tlumí phishingovou amplitudu",
            ham=amp(1.1),
            damp_phishing=0.25,
            damp_spam=0.55,
        ))
    elif spf_pass or dkim_pass:
        signals.append(make_signal(
            "auth_partial",
            "Částečně prošla autentizace (jen SPF nebo jen DKIM)",
            ham=amp(0.5),
            damp_phishing=0.6,
        ))

    if dmarc_fail:
        signals.append(make_signal(
            "dmarc_fail",
            "DMARC selhal - odesílatel pravděpodobně padělán",
            phishing=amp(1.2),
            spam=amp(0.4),
        ))
    elif spf_fail or dkim_fail:
        signals.append(make_signal(
            "auth_fail",
            "SPF/DKIM selhal",
            phishing=amp(0.8),
            spam=amp(0.5),
        ))
    return signals


def detect_sender_mismatch(mail: ParsedEmail) -> list[Signal]:
    """Neshoda From / Reply-To / Return-Path a spoofing zobrazovaného jména."""
    signals: list[Signal] = []
    fd = mail.from_domain
    rd = mail.reply_to_domain
    rp = mail.return_path_domain

    if fd and rd and rd != fd:
        signals.append(make_signal(
            "replyto_mismatch",
            f"Reply-To doména ({rd}) se liší od From ({fd})",
            phishing=amp(1.0),
            spam=amp(0.3),
        ))
    if fd and rp and rp != fd:
        signals.append(make_signal(
            "returnpath_mismatch",
            f"Return-Path doména ({rp}) se liší od From ({fd})",
            phishing=amp(0.5),
            spam=amp(0.5),
        ))

    # Display-name spoofing: jméno předstírá značku, ale doména nesedí.
    name = _normtext(mail.from_name)
    brand_in_name = next((b for b in _BRANDS if b in name), None)
    if brand_in_name and fd:
        brand_token = brand_in_name.split()[0]
        if brand_token not in fd:
            extra = " (navíc freemail)" if fd in _FREEMAIL else ""
            signals.append(make_signal(
                "display_name_spoof",
                f"Zobrazované jméno odkazuje na '{brand_in_name}', "
                f"ale doména je '{fd}'{extra}",
                phishing=amp(1.3 if fd in _FREEMAIL else 1.0),
            ))
    return signals


def detect_links(mail: ParsedEmail) -> list[Signal]:
    """Analýza odkazů: IP hosty, zkracovače, punycode, neshoda kotvy a cíle."""
    signals: list[Signal] = []
    domains = mail.url_domains
    if not domains:
        return signals

    for host in domains:
        if _IP_HOST_RE.match(host):
            signals.append(make_signal(
                "ip_url",
                f"Odkaz míří přímo na IP adresu ({host}) místo domény",
                phishing=amp(1.2),
            ))
        if host.startswith("xn--") or ".xn--" in host:
            signals.append(make_signal(
                "punycode_url",
                f"Punycode/homografní doména v odkazu ({host})",
                phishing=amp(1.1),
            ))
        if host in _SHORTENERS:
            signals.append(make_signal(
                "url_shortener",
                f"Zkracovač URL skrývá skutečný cíl ({host})",
                phishing=amp(0.5),
                spam=amp(0.6),
            ))

    # "@" v URL (trik s userinfo) nebo příliš mnoho subdomén.
    for url in mail.urls:
        path = url.split("//", 1)[-1]
        host_part = path.split("/", 1)[0]
        if "@" in host_part:
            signals.append(make_signal(
                "url_userinfo",
                f"URL obsahuje '@' před hostitelem (maskuje cíl): {url}",
                phishing=amp(1.1),
            ))
        if host_part.count(".") >= 4:
            signals.append(make_signal(
                "url_many_subdomains",
                f"Mnoho subdomén v hostiteli ({host_part}) - typické pro phishing",
                phishing=amp(0.6),
            ))

    # Neshoda viditelného textu odkazu a skutečného cíle.
    for text, url in zip(mail.anchor_texts, mail.urls):
        text_dom = _maybe_domain(text)
        url_host = _host_of(url)
        if text_dom and url_host and _root_domain(text_dom) != _root_domain(url_host):
            signals.append(make_signal(
                "anchor_mismatch",
                f"Text odkazu ukazuje '{text_dom}', ale míří na '{url_host}'",
                phishing=amp(1.2),
            ))

    # Hodně různých cílových domén -> rozesílka / spam.
    distinct = len(set(_root_domain(d) for d in domains))
    if distinct >= 4:
        signals.append(make_signal(
            "many_link_domains",
            f"Mnoho různých cílových domén v odkazech ({distinct})",
            spam=amp(0.7),
        ))
    return signals


def detect_language(mail: ParsedEmail) -> list[Signal]:
    """Jazykové vzorce: naléhavost, žádost o údaje, reklamní/podvodné fráze."""
    signals: list[Signal] = []
    text = _normtext(mail.all_text)
    if not text:
        return signals

    urgency = _count_hits(text, _URGENCY)
    if urgency:
        signals.append(make_signal(
            "urgency",
            f"Naléhavý/nátlakový jazyk: {', '.join(urgency[:4])}",
            phishing=amp(min(1.0, 0.45 * len(urgency))),
            spam=amp(0.2),
        ))

    cred = _count_hits(text, _CREDENTIAL)
    if cred:
        signals.append(make_signal(
            "credential_request",
            f"Žádost o citlivé údaje: {', '.join(cred[:4])}",
            phishing=amp(min(1.3, 0.6 * len(cred))),
        ))

    money = _count_hits(text, _MONEY_SPAM)
    if money:
        signals.append(make_signal(
            "promo_money",
            f"Reklamní/podvodné fráze: {', '.join(money[:5])}",
            spam=amp(min(1.2, 0.35 * len(money))),
            phishing=amp(0.15 * len(money)),
        ))

    # Kombinace naléhavosti + žádosti o údaje je klasický phishing.
    if urgency and cred:
        signals.append(make_signal(
            "urgency_plus_credentials",
            "Naléhavost spojená s žádostí o přihlašovací údaje (klasický phishing)",
            phishing=amp(1.0),
        ))
    return signals


def detect_formatting(mail: ParsedEmail) -> list[Signal]:
    """Formátování: KŘIK velkými písmeny, vykřičníky, prázdné tělo, HTML-only."""
    signals: list[Signal] = []
    subject = mail.subject

    letters = [c for c in subject if c.isalpha()]
    if len(letters) >= 6:
        caps_ratio = sum(c.isupper() for c in letters) / len(letters)
        if caps_ratio > 0.6:
            signals.append(make_signal(
                "shouting_subject",
                f"Předmět převážně VELKÝMI písmeny ({caps_ratio:.0%})",
                spam=amp(0.6),
            ))

    exclamations = mail.subject.count("!") + mail.all_text.count("!")
    if exclamations >= 3:
        signals.append(make_signal(
            "many_exclamations",
            f"Mnoho vykřičníků ({exclamations})",
            spam=amp(min(0.6, 0.15 * exclamations)),
        ))

    if mail.html_body and not mail.text_body.strip():
        signals.append(make_signal(
            "html_only",
            "Pouze HTML tělo bez textové alternativy",
            spam=amp(0.35),
        ))
    return signals


def detect_attachments(mail: ParsedEmail) -> list[Signal]:
    """Rizikové přílohy (spustitelné, skripty, HTML formuláře)."""
    signals: list[Signal] = []
    for name in mail.attachment_names:
        lower = name.lower()
        if any(lower.endswith(ext) for ext in _RISKY_EXT):
            signals.append(make_signal(
                "risky_attachment",
                f"Riziková příloha: {name}",
                phishing=amp(1.0),
                spam=amp(0.3),
            ))
        if lower.endswith(".zip") or lower.endswith(".rar") or lower.endswith(".7z"):
            signals.append(make_signal(
                "archive_attachment",
                f"Archivní příloha může skrývat spustitelný obsah: {name}",
                phishing=amp(0.5),
            ))
    return signals


# -- pomocné funkce -------------------------------------------------------


def _host_of(url: str) -> str:
    m = re.match(r"https?://([^/\s:@]+@)?([^/\s:]+)", url, re.IGNORECASE)
    return m.group(2).lower() if m else ""


def _root_domain(host: str) -> str:
    """Hrubé "registrovatelné" doménové jádro (poslední dvě části)."""
    host = host.strip().lower().lstrip("www.")
    parts = [p for p in host.split(".") if p]
    if len(parts) <= 2:
        return ".".join(parts)
    return ".".join(parts[-2:])


def _maybe_domain(text: str) -> str:
    m = re.search(r"([A-Za-z0-9\-]+\.)+[A-Za-z]{2,}", text)
    return m.group(0).lower() if m else ""


#: Pořadí spuštění všech detektorů.
ALL_DETECTORS: tuple[Detector, ...] = (
    detect_authentication,
    detect_sender_mismatch,
    detect_links,
    detect_language,
    detect_formatting,
    detect_attachments,
)


def run_detectors(mail: ParsedEmail) -> list[Signal]:
    """Spustí všechny detektory a vrátí sloučený seznam signálů."""
    signals: list[Signal] = []
    for det in ALL_DETECTORS:
        signals.extend(det(mail))
    return signals
