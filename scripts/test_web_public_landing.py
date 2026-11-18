"""Public landing pages must never bypass Khanya's existing authenticated POS flow."""
from html.parser import HTMLParser
from pathlib import Path

root=Path(__file__).resolve().parents[1]
html=(root/'apps/web/index.html').read_text(encoding='utf-8')
js=(root/'apps/web/app.js').read_text(encoding='utf-8')
css=(root/'apps/web/style.css').read_text(encoding='utf-8')

class PageParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids=[]
        self.links=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if 'id' in a: self.ids.append(a['id'])
        if 'data-public-page' in a: self.links.append(a['data-public-page'])

def test_public_landing():
    doc=PageParser()
    doc.feed(html)
    assert len(doc.ids)==len(set(doc.ids)), "Duplicate element IDs"
    for page in ['home','features','how']:
        assert 'public-'+page in doc.ids
        assert page in doc.links
    for required in ['public-pages','public-navigation','login-view','login-form',
                     'login-back-home','app-view','mobile-bottom-nav',
                     'overview-view','receipt-print']:
        assert required in doc.ids, required
    assert doc.links.count('login')>=2
    assert 'id="login-view" class="login-wrap" hidden' in html
    assert 'id="app-view" hidden' in html
    assert "showPublicPage('home')" in js
    assert "function showPublicPage(page)" in js
    assert "if(state.access && state.me)return" in js
    assert "for(const link of document.querySelectorAll?.('[data-public-page]')" in js
    assert "$('public-navigation').hidden = true" in js
    assert "$('public-pages').hidden = true" in js
    assert "request('/auth/login'" in js
    assert "fillTenants();" in js
    assert "openView('overview');" in js
    assert '.landing-preview' in css
    assert '@media(max-width:700px)' in css
    assert 'prefers-reduced-motion:reduce' in css

if __name__=='__main__':
    test_public_landing()
    print('Public landing page contract checks passed')
