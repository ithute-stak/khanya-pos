"""Regression checks for task-focused Khanya POS browser screens.

Run: python3 scripts/test_web_task_screens.py
"""
from html.parser import HTMLParser
from pathlib import Path

root = Path(__file__).resolve().parents[1]
html = (root / "apps/web/index.html").read_text(encoding="utf-8")
js = (root / "apps/web/app.js").read_text(encoding="utf-8")
css = (root / "apps/web/style.css").read_text(encoding="utf-8")

class Elements(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.form_buttons = []
        self.back_buttons = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "id" in a: self.ids.append(a["id"])
        if "data-open-form" in a: self.form_buttons.append(a["data-open-form"])
        if "data-back-view" in a: self.back_buttons.append(a["data-back-view"])

def check():
    el = Elements()
    el.feed(html)
    assert len(el.ids) == len(set(el.ids)), "Duplicate ID in page"
    for name in ["catalog", "stock", "customers", "suppliers", "expenses"]:
        assert name + "-view" in el.ids, name
        assert name + "-form-view" in el.ids, name
        assert el.form_buttons.count(name) == 1, name
        assert el.back_buttons.count(name) == 1, name
    assert "purchasing-view" in el.ids
    assert "purchases-view" in el.ids
    assert el.back_buttons.count("purchasing") == 1
    for value in ["product-form", "stock-form", "customer-form",
                  "supplier-form", "expense-form", "purchase-order-form",
                  "cart-items", "complete-sale"]:
        assert el.ids.count(value) == 1, value
    for value in ["checkout-grid", "mobile-show-cart", "mobile-cart-back",
                  "mobile-cart-count", "purchasing-purchases-open"]:
        assert el.ids.count(value) == 1, value
    assert "data-open-form" in js
    assert "data-back-view" in js
    assert "openView(section+'-form')" in js
    assert "if(name==='purchasing' || name==='purchases')loadPurchasing()" in js
    assert "mobile-cart-mode" in css
    assert ".screen-content" in css
    assert "receipt-print" in html
    print("Task-focused screen contract checks passed")

if __name__ == "__main__":
    check()
