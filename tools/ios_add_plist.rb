# Adds ios/App/App/GoogleService-Info.plist to the App target (needed by Firebase on iOS).
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
target = project.targets.find { |t| t.name == 'App' }
group = project.main_group['App']
unless group.files.any? { |f| f.path == 'GoogleService-Info.plist' }
  ref = group.new_file('GoogleService-Info.plist')
  target.add_resources([ref])
  project.save
  puts 'GoogleService-Info.plist added to Xcode project'
end
