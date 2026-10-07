require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

# Used only when the iOS project is managed with CocoaPods.
# Projects created with Swift Package Manager use Package.swift instead.
Pod::Spec.new do |s|
  s.name = 'BwpNative'
  s.version = package['version']
  s.summary = package['description']
  s.license = 'UNLICENSED'
  s.homepage = 'https://bill.bwpexperts.com'
  s.author = package['author']
  s.source = { :git => 'https://bill.bwpexperts.com', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
end
