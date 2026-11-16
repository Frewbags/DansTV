"""Static regression guard for the offline DansTV launcher.

This is a source-level gate, not a network packet capture or a guarantee that
Samsung Tizen services do not communicate independently.
"""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'app'
errors = []
scripts = list(APP.rglob('*.js'))
html = list(APP.rglob('*.html'))
css = list(APP.rglob('*.css'))
# Restrict network interfaces in packaged source, not in development tools/tests.
prohibited_js = {
    'fetch': r'\bfetch\s*\(',
    'XMLHttpRequest': r'\bXMLHttpRequest\b',
    'WebSocket': r'\bWebSocket\b',
    'EventSource': r'\bEventSource\b',
    'sendBeacon': r'\bsendBeacon\s*\(',
    'external resource': r'(?:https?:)?//[a-z0-9.-]+\.[a-z]{2,}',
}
for path in scripts:
    text = path.read_text(encoding='utf-8')
    for name, expression in prohibited_js.items():
        if re.search(expression, text, flags=re.I):
            errors.append(f'{path.relative_to(ROOT)}: forbidden {name}')
for path in html + css:
    text = path.read_text(encoding='utf-8')
    # Allow documentation comments but never external HTML/CSS resource references.
    for expression in [
        r'<(?:script|img|iframe|link|source)\b[^>]*(?:src|href)\s*=\s*["\']\s*(?:https?:)?//',
        r'@import\s+(?:url\s*\(\s*)?["\']?\s*(?:https?:)?//',
        r'url\s*\(\s*["\']?\s*(?:https?:)?//',
    ]:
        if re.search(expression, text, flags=re.I):
            errors.append(f'{path.relative_to(ROOT)}: external resource reference')
manifest = ET.parse(APP / 'config.xml').getroot()
for element in manifest:
    if element.tag.endswith('privilege') and 'internet' in element.get('name', '').lower():
        errors.append('app/config.xml: internet privilege')
if errors:
    raise SystemExit('Offline launcher check failed:\n' + '\n'.join(errors))
print(f'Offline launcher static check passed ({len(scripts)} JS, {len(html)} HTML, {len(css)} CSS files).')
print('Does not verify Samsung OS traffic, dynamic script execution or external app requests.')
