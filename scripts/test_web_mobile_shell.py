"""Static regression checks for Khanya POS mobile browser shell."""
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "apps/web/index.html").read_text(encoding="utf-8")
JS = (ROOT / "apps/web/app.js").read_text(encoding="utf-8")
CSS = (ROOT / "apps/web/style.css").read_text(encoding="utf-8")


class Inspector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.mobile_views = []
        self.more_views = []
    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        if "id" in data:
            self.ids.append(data["id"])
        if "data-mobile-view" in data:
            self.mobile_views.append(data["data-mobile-view"])
        if "data-mobile-more-view" in data:
            self.more_views.append(data["data-mobile-more-view"])


def test_mobile_nav_markup_and_navigation_sections():
    inspector = Inspector()
    inspector.feed(HTML)
    assert len(inspector.ids) == len(set(inspector.ids)), "Duplicate DOM IDs"
    assert inspector.mobile_views == ["checkout", "catalog", "stock", "customers"]
    assert inspector.more_views == [
        "overview", "suppliers", "expenses", "reports", "staff",
        "purchasing", "history", "qr",
    ]
    assert all(f'{name}-view' in inspector.ids for name in inspector.mobile_views + inspector.more_views)
    assert "mobile-bottom-nav" in inspector.ids
    assert "mobile-more-menu" in inspector.ids
    assert "account-menu" in inspector.ids


def test_mobile_navigation_preserves_existing_pos_actions():
    assert "function openView(name)" in JS
    assert "syncMobileNavigation(name)" in JS
    assert "closeMobileMenus();" in JS
    assert "openView(action.dataset.mobileView)" in JS
    assert "openView(action.dataset.mobileMoreView)" in JS
    assert "setAccountMenu(opening)" in JS
    assert "$('account-logout').addEventListener('click',()=>signOut())" in JS
    assert "$('mobile-bottom-nav').hidden = true" in JS
    assert "$('mobile-bottom-nav').hidden = false" in JS
    assert "document.querySelectorAll('.tab')" in JS


def test_mobile_css_respects_login_and_receipt_printing():
    assert "@media(max-width:700px)" in CSS
    assert ".mobile-bottom-nav:not([hidden])" in CSS
    assert ".mobile-more-menu:not([hidden])" in CSS
    assert "env(safe-area-inset-bottom)" in CSS
    assert ".mobile-bottom-nav,.mobile-more-menu,.account-menu{display:none!important}" in CSS
    assert 'id="receipt-print"' in HTML


if __name__ == "__main__":
    test_mobile_nav_markup_and_navigation_sections()
    test_mobile_navigation_preserves_existing_pos_actions()
    test_mobile_css_respects_login_and_receipt_printing()
    print("Mobile web shell checks passed")
