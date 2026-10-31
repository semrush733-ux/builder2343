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

# ---------- Login (Firebase Authentication) ----------
import os
if os.environ.get('FIREBASE_ENABLED') == '1':
    var_file = pathlib.Path('android/variables.gradle')
    v = var_file.read_text()
    if 'rgcfaIncludeGoogle' not in v:
        v = v.replace('ext {', 'ext {\n    rgcfaIncludeGoogle = true\n    rgcfaIncludeFacebook = %s' % ('true' if os.environ.get('FB_APP_ID') else 'false'), 1)
        var_file.write_text(v)
    print('variables.gradle: Google login on, Facebook', bool(os.environ.get('FB_APP_ID')))
    fb_id = os.environ.get('FB_APP_ID', '').strip()
    fb_token = os.environ.get('FB_CLIENT_TOKEN', '').strip()
    if fb_id:
        strings = res / 'values' / 'strings.xml'
        st = strings.read_text()
        if 'facebook_app_id' not in st:
            st = st.replace('</resources>', '    <string name="facebook_app_id">%s</string>\n    <string name="facebook_client_token">%s</string>\n    <string name="fb_login_protocol_scheme">fb%s</string>\n</resources>' % (fb_id, fb_token, fb_id))
            strings.write_text(st)
        text = manifest.read_text()
        if 'com.facebook.sdk.ApplicationId' not in text:
            fb = """<meta-data android:name="com.facebook.sdk.ApplicationId" android:value="@string/facebook_app_id"/>
        <meta-data android:name="com.facebook.sdk.ClientToken" android:value="@string/facebook_client_token"/>
        <activity android:name="com.facebook.FacebookActivity" android:configChanges="keyboard|keyboardHidden|screenLayout|screenSize|orientation" android:label="@string/app_name" />
        <activity android:name="com.facebook.CustomTabActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="@string/fb_login_protocol_scheme" />
            </intent-filter>
        </activity>
    """
            text = text.replace('</application>', fb + '</application>', 1)
            manifest.write_text(text)
        print('Facebook login configured')
