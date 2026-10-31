"""Patches the generated Capacitor iOS project: app icon, splash screen, portrait-only, display name."""
import json, pathlib, plistlib, shutil

app = pathlib.Path('ios/App/App')
assets = app / 'Assets.xcassets'

# App icon: single 1024x1024 icon (Xcode generates all sizes from it).
icon_dir = assets / 'AppIcon.appiconset'
for old in icon_dir.glob('*.png'):
    old.unlink()
shutil.copy('assets/icon-1024.png', icon_dir / 'AppIcon-1024.png')
(icon_dir / 'Contents.json').write_text(json.dumps({
    "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2))
print('icon ok')

# Splash: replace every image in Splash.imageset.
splash_dir = assets / 'Splash.imageset'
n = 0
for img in splash_dir.glob('*.png'):
    shutil.copy('assets/splash-2732.png', img)
    n += 1
print('splash images replaced:', n)

# Info.plist: portrait only, display name, full screen.
plist_path = app / 'Info.plist'
with open(plist_path, 'rb') as f:
    pl = plistlib.load(f)
pl['CFBundleDisplayName'] = 'Block Merge'
pl['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait']
pl['UISupportedInterfaceOrientations~ipad'] = ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown']
pl['UIRequiresFullScreen'] = True
pl['UIStatusBarStyle'] = 'UIStatusBarStyleLightContent'
pl['UIViewControllerBasedStatusBarAppearance'] = False
pl['ITSAppUsesNonExemptEncryption'] = False
# AdMob
ads = json.loads(pathlib.Path('ads.json').read_text())
pl['GADApplicationIdentifier'] = ads['ios']['appId']
pl['NSUserTrackingUsageDescription'] = 'This lets us show you ads that are more relevant to you.'
pl['SKAdNetworkItems'] = [{'SKAdNetworkIdentifier': 'cstr6suwn9.skadnetwork'}]
import os, re, subprocess
if os.environ.get('FIREBASE_ENABLED') == '1':
    gsi = app / 'GoogleService-Info.plist'
    with open(gsi, 'rb') as f:
        g = plistlib.load(f)
    schemes = [g['REVERSED_CLIENT_ID']]
    fb_id = os.environ.get('FB_APP_ID', '').strip()
    if fb_id:
        schemes.append('fb' + fb_id)
        pl['FacebookAppID'] = fb_id
        pl['FacebookClientToken'] = os.environ.get('FB_CLIENT_TOKEN', '').strip()
        pl['FacebookDisplayName'] = 'Block Merge'
        pl['LSApplicationQueriesSchemes'] = ['fbapi', 'fb-messenger-share-api']
    pl['CFBundleURLTypes'] = [{'CFBundleURLSchemes': [sc]} for sc in schemes]
    # Podfile: Google (+ Facebook) sign-in subspecs
    podfile = pathlib.Path('ios/App/Podfile')
    pf = podfile.read_text()
    path = "'../../node_modules/@capacitor-firebase/authentication'"
    extra = "  pod 'CapacitorFirebaseAuthentication/Google', :path => %s\n" % path
    if fb_id:
        extra += "  pod 'CapacitorFirebaseAuthentication/Facebook', :path => %s\n" % path
    if 'CapacitorFirebaseAuthentication/Google' not in pf:
        pf = re.sub(r"(target 'App' do\n\s*capacitor_pods\n)", lambda m: m.group(1) + extra, pf, count=1)
        podfile.write_text(pf)
    # add GoogleService-Info.plist to the Xcode project
    subprocess.run(['ruby', 'tools/ios_add_plist.rb'], check=True)
    # AppDelegate: Facebook SDK hooks
    if fb_id:
        ad = app / 'AppDelegate.swift'
        a = ad.read_text()
        if 'FBSDKCoreKit' not in a:
            a = a.replace('import Capacitor', 'import Capacitor\nimport FBSDKCoreKit', 1)
            a = re.sub(r'(didFinishLaunchingWithOptions launchOptions: \[UIApplication\.LaunchOptionsKey: Any\]\?\) -> Bool \{\n)',
                       lambda m: m.group(1) + '        FBSDKCoreKit.ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)\n', a, count=1)
            a = re.sub(r'(open url: URL, options: \[UIApplication\.OpenURLOptionsKey: Any\] = \[:\]\) -> Bool \{\n)',
                       lambda m: m.group(1) + '        if FBSDKCoreKit.ApplicationDelegate.shared.application(app, open: url, sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String, annotation: options[UIApplication.OpenURLOptionsKey.annotation]) { return true }\n', a, count=1)
            ad.write_text(a)
            print('AppDelegate: Facebook hooks added', 'FBSDKCoreKit.ApplicationDelegate.shared.application(app' in a)
    print('Firebase login configured for iOS')

with open(plist_path, 'wb') as f:
    plistlib.dump(pl, f)
print('Info.plist ok')
