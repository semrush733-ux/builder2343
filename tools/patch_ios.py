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
with open(plist_path, 'wb') as f:
    plistlib.dump(pl, f)
print('Info.plist ok')
