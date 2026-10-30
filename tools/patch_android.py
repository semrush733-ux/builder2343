"""Patches the generated Capacitor Android project: portrait lock, launcher icons, splash screen."""
import pathlib, re, shutil, sys

root = pathlib.Path('android/app/src/main')
manifest = root / 'AndroidManifest.xml'
text = manifest.read_text()
if 'screenOrientation' not in text:
    text, n = re.subn(r'<activity(\s)', r'<activity android:screenOrientation="portrait"\1', text, count=1)
    if n != 1:
        sys.exit('Could not find <activity> in AndroidManifest.xml')
import json
ads = json.loads(pathlib.Path('ads.json').read_text())
if 'com.google.android.gms.ads.APPLICATION_ID' not in text:
    meta = ('<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s"/>\n'
            '        <meta-data android:name="com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT" android:value="true"/>\n    ' % ads['android']['appId'])
    text, n = re.subn(r'(</application>)', meta + r'\1', text, count=1)
    if n != 1:
        sys.exit('Could not find </application> in AndroidManifest.xml')
manifest.write_text(text)
print('manifest: portrait + AdMob app id ok')

res = root / 'res'
# Use the plain PNG launcher icons (remove the adaptive-icon XML that points at the Capacitor default).
shutil.rmtree(res / 'mipmap-anydpi-v26', ignore_errors=True)
for src in pathlib.Path('android-overrides/res').rglob('*.png'):
    dst = res / src.relative_to('android-overrides/res')
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dst)
print('icons copied')

# Replace every Capacitor default splash image with the game splash.
count = 0
for splash in res.rglob('splash.png'):
    shutil.copy('assets/splash-portrait.png', splash)
    count += 1
print('splash images replaced:', count)

# Dark background behind the WebView while it loads.
colors = res / 'values' / 'colors.xml'
if colors.exists():
    c = colors.read_text()
    c = re.sub(r'(<color name="colorPrimary">)[^<]*', r'\g<1>#0d1024', c)
    c = re.sub(r'(<color name="colorPrimaryDark">)[^<]*', r'\g<1>#0d1024', c)
    colors.write_text(c)
    print('colors.xml patched')
