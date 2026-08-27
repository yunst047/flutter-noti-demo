#!/usr/bin/env ruby
# Puts GoogleService-Info.plist into the Runner target's Copy Bundle Resources.
#
# This exists because the file being *on disk* is not enough and the failure is
# silent: `Firebase.initializeApp()` is called with no options, so on iOS it
# reads the plist out of the app bundle. Miss the target membership and the file
# never gets copied, the app logs `[core/not-initialized]`, and everything looks
# like a credentials problem.
#
# The usual instruction is "drag it into Xcode and tick Runner" — the tick being
# the part people miss. This does the same edit, and is idempotent.
#
#   cp ~/Downloads/GoogleService-Info.plist ios/Runner/
#   ruby tool/link_google_services.rb
#
# Verify afterwards, which is the only check that actually proves anything:
#
#   flutter build ios --simulator --debug
#   ls build/ios/iphonesimulator/Runner.app/GoogleService-Info.plist
#
# ---------------------------------------------------------------------------
# DO NOT COMMIT the project.pbxproj change this makes.
#
# The plist itself is gitignored, so a checkout whose project references it but
# does not contain it fails the build outright, before anything useful happens:
#
#   Error (Xcode): Build input file cannot be found:
#     '.../ios/Runner/GoogleService-Info.plist'
#
# The committed project therefore does not reference the plist at all, and every
# clone runs this script once after supplying its own. Both states are verified
# to build.
# ---------------------------------------------------------------------------

require 'xcodeproj'

PLIST = 'GoogleService-Info.plist'
project_path = File.expand_path('ios/Runner.xcodeproj', Dir.pwd)
plist_path = File.expand_path("ios/Runner/#{PLIST}", Dir.pwd)

unless File.exist?(plist_path)
  abort <<~MSG
    #{PLIST} not found at ios/Runner/#{PLIST}

    Download it from the Firebase console — Project settings > Your apps > the iOS
    app registered as com.f0h.flt-noti-demo — and put it there first. It is
    gitignored by design; see docs/SETUP.md section D.
  MSG
end

# The bundle ID in the plist must match the app, or FCM answers SENDER_ID_MISMATCH
# on send rather than failing at registration — an error that reads like a key
# problem and is really a naming one.
bundle_id = `/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" #{plist_path.inspect} 2>/dev/null`.strip
expected = 'com.f0h.flt-noti-demo'
if !bundle_id.empty? && bundle_id != expected
  abort "#{PLIST} is for #{bundle_id}, but this app is #{expected}. " \
        'Register a separate iOS app in Firebase for this bundle ID.'
end

project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'
group = project.main_group['Runner'] or abort 'no Runner group'

ref = group.files.find { |f| f.path == PLIST } || group.new_reference(PLIST)

if runner.resources_build_phase.files.any? { |f| f.file_ref == ref }
  puts "already linked: #{PLIST} is in Runner's resources"
else
  runner.resources_build_phase.add_file_reference(ref)
  project.save
  puts "linked: #{PLIST} added to Runner's Copy Bundle Resources"
end
