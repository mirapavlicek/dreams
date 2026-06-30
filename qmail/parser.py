"""Rozbor surového e-mailu (RFC 822 / .eml) do normalizované struktury.

Záměrně používá jen standardní knihovnu (``email``), takže nevyžaduje
žádné externí závislosti.
"""

from __future__ import annotations

import email
import re
from dataclasses import dataclass, field
from email.message import Message
from email.utils import getaddresses, parseaddr
from html.parser import HTMLParser

_URL_RE = re.compile(r"""https?://[^\s<>"')]+""", re.IGNORECASE)
_ADDR_DOMAIN_RE = re.compile(r"@([A-Za-z0-9.\-]+)")


class _HTMLTextExtractor(HTMLParser):
    """Vytáhne z HTML viditelný text a cílové URL z atributů href."""

    def __init__(self) -> None:
        super().__init__()
        self.text_parts: list[str] = []
        self.hrefs: list[str] = []
        self.anchor_texts: list[str] = []
        self._in_anchor = False
        self._current_href: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "a":
            self._in_anchor = True
            for key, value in attrs:
                if key.lower() == "href" and value:
                    self.hrefs.append(value)
                    self._current_href = value

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == "a":
            self._in_anchor = False
            self._current_href = None

    def handle_data(self, data: str) -> None:
        stripped = data.strip()
        if stripped:
            self.text_parts.append(stripped)
            if self._in_anchor:
                self.anchor_texts.append(stripped)

    @property
    def text(self) -> str:
        return " ".join(self.text_parts)


@dataclass
class ParsedEmail:
    """Normalizovaná reprezentace e-mailu pro detektory."""

    headers: dict[str, str] = field(default_factory=dict)
    from_name: str = ""
    from_addr: str = ""
    reply_to_addr: str = ""
    return_path_addr: str = ""
    to_addrs: list[str] = field(default_factory=list)
    subject: str = ""
    text_body: str = ""
    html_body: str = ""
    urls: list[str] = field(default_factory=list)
    anchor_texts: list[str] = field(default_factory=list)
    auth_results: str = ""
    received_spf: str = ""
    has_attachments: bool = False
    attachment_names: list[str] = field(default_factory=list)

    @property
    def from_domain(self) -> str:
        return _domain_of(self.from_addr)

    @property
    def reply_to_domain(self) -> str:
        return _domain_of(self.reply_to_addr)

    @property
    def return_path_domain(self) -> str:
        return _domain_of(self.return_path_addr)

    @property
    def all_text(self) -> str:
        return f"{self.subject}\n{self.text_body}\n{self.html_body}".strip()

    @property
    def url_domains(self) -> list[str]:
        return [_url_domain(u) for u in self.urls if _url_domain(u)]


def _domain_of(addr: str) -> str:
    if not addr:
        return ""
    m = _ADDR_DOMAIN_RE.search(addr)
    return m.group(1).lower() if m else ""


def _url_domain(url: str) -> str:
    m = re.match(r"https?://([^/\s:]+)", url, re.IGNORECASE)
    return m.group(1).lower() if m else ""


def _decoded_body(part: Message) -> str:
    payload = part.get_payload(decode=True)
    if payload is None:
        raw = part.get_payload()
        return raw if isinstance(raw, str) else ""
    charset = part.get_content_charset() or "utf-8"
    try:
        return payload.decode(charset, errors="replace")
    except (LookupError, UnicodeDecodeError):
        return payload.decode("utf-8", errors="replace")


def parse_email(raw: str | bytes) -> ParsedEmail:
    """Rozparsuje surový e-mail (text nebo bajty) do :class:`ParsedEmail`."""
    if isinstance(raw, bytes):
        msg = email.message_from_bytes(raw)
    else:
        msg = email.message_from_string(raw)

    result = ParsedEmail()
    result.headers = {k.lower(): v for k, v in msg.items()}

    from_name, from_addr = parseaddr(msg.get("From", ""))
    result.from_name = from_name
    result.from_addr = from_addr.lower()
    _, reply_to = parseaddr(msg.get("Reply-To", ""))
    result.reply_to_addr = reply_to.lower()
    _, return_path = parseaddr(msg.get("Return-Path", ""))
    result.return_path_addr = return_path.lower()
    result.to_addrs = [a.lower() for _, a in getaddresses([msg.get("To", "")]) if a]
    result.subject = str(msg.get("Subject", ""))
    result.auth_results = str(msg.get("Authentication-Results", ""))
    result.received_spf = str(msg.get("Received-SPF", ""))

    text_chunks: list[str] = []
    html_chunks: list[str] = []

    if msg.is_multipart():
        for part in msg.walk():
            if part.is_multipart():
                continue
            ctype = part.get_content_type()
            disp = str(part.get("Content-Disposition", ""))
            filename = part.get_filename()
            if filename or "attachment" in disp.lower():
                result.has_attachments = True
                if filename:
                    result.attachment_names.append(filename)
                continue
            if ctype == "text/plain":
                text_chunks.append(_decoded_body(part))
            elif ctype == "text/html":
                html_chunks.append(_decoded_body(part))
    else:
        if msg.get_content_type() == "text/html":
            html_chunks.append(_decoded_body(msg))
        else:
            text_chunks.append(_decoded_body(msg))

    result.text_body = "\n".join(text_chunks).strip()
    raw_html = "\n".join(html_chunks).strip()
    result.html_body = raw_html

    urls: list[str] = []
    urls.extend(_URL_RE.findall(result.text_body))

    if raw_html:
        extractor = _HTMLTextExtractor()
        try:
            extractor.feed(raw_html)
        except Exception:  # pragma: no cover - HTMLParser je odolný
            pass
        result.anchor_texts = extractor.anchor_texts
        urls.extend(extractor.hrefs)
        urls.extend(_URL_RE.findall(extractor.text))
        # Když není čistý text, použij viditelný text z HTML.
        if not result.text_body:
            result.text_body = extractor.text

    # Deduplikace při zachování pořadí.
    seen: set[str] = set()
    deduped: list[str] = []
    for u in urls:
        u = u.rstrip(".,);")
        if u and u not in seen and u.lower().startswith("http"):
            seen.add(u)
            deduped.append(u)
    result.urls = deduped

    return result
