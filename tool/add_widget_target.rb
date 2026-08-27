#!/usr/bin/env ruby
# Adds the DeliveryWidget Live Activity extension to Runner.xcodeproj.
#
# Xcode's "File > New > Target" wizard is the documented way to do this; it is a
# GUI-only flow, so the same edits are made here through the xcodeproj gem that
# CocoaPods ships. Idempotent: re-running replaces the target rather than adding
# a second one.

require 'xcodeproj'

PROJECT   = File.expand_path('ios/Runner.xcodeproj', Dir.pwd)
TARGET    = 'DeliveryWidget'
APP_ID    = 'com.f0h.flt-noti-demo'
WIDGET_ID = "#{APP_ID}.DeliveryWidget"

project = Xcodeproj::Project.open(PROJECT)
app = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

# --- clean out a previous run -------------------------------------------------
project.targets.select { |t| t.name == TARGET }.each do |t|
  app.dependencies.select { |d| d.target == t }.each { |d| app.dependencies.delete(d) }
  t.remove_from_project
end
project.main_group.children.select { |g| g.respond_to?(:name) && g.name == TARGET }
       .each(&:remove_from_project)
app.build_phases.select { |p|
  p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && p.name == 'Embed App Extensions'
}.each { |p| app.build_phases.delete(p) }

# --- the extension target ----------------------------------------------------
widget = project.new_target(:app_extension, TARGET, :ios, '16.2')

group = project.main_group.new_group(TARGET, TARGET)
%w[DeliveryAttributes.swift DeliveryLiveActivity.swift DeliveryWidgetBundle.swift].each do |f|
  widget.add_file_references([group.new_reference(f)])
end
group.new_reference('Info.plist')
group.new_reference('DeliveryWidget.entitlements')
xcconfig = group.new_reference('DeliveryWidget.xcconfig')

widget.build_configurations.each do |config|
  config.base_configuration_reference = xcconfig
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER'           => WIDGET_ID,
    'PRODUCT_NAME'                        => '$(TARGET_NAME)',
    'INFOPLIST_FILE'                      => 'DeliveryWidget/Info.plist',
    'CODE_SIGN_ENTITLEMENTS'              => 'DeliveryWidget/DeliveryWidget.entitlements',
    'CODE_SIGN_STYLE'                     => 'Automatic',
    # ActivityKit is 16.1; ActivityContent with a stale date is 16.2, and the
    # plugin uses it on the app side, so both halves target the same floor.
    'IPHONEOS_DEPLOYMENT_TARGET'          => '16.2',
    'SWIFT_VERSION'                       => '5.0',
    'TARGETED_DEVICE_FAMILY'              => '1,2',
    'SKIP_INSTALL'                        => 'YES',
    'GENERATE_INFOPLIST_FILE'             => 'NO',
    # MARKETING_VERSION and CURRENT_PROJECT_VERSION deliberately come from
    # DeliveryWidget.xcconfig — a target-level setting here would override it.
    'LD_RUNPATH_SEARCH_PATHS'             =>['$(inherited)', '@executable_path/Frameworks',
                                              '@executable_path/../../Frameworks'],
    'SWIFT_EMIT_LOC_STRINGS'              => 'YES',
    'ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOL_EXTENSIONS' => 'YES'
  )
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config.name == 'Debug'
end

# --- embed it in the app ------------------------------------------------------
app.add_dependency(widget)

embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(widget.product_reference, true)
embed.files.last.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# The extension must be built and copied in before the Flutter script phases
# that assemble and thin the .app, otherwise it is stripped back out.
app.build_phases.delete(embed)
app.build_phases.insert(app.build_phases.index { |p|
  p.respond_to?(:name) && p.name.to_s.include?('Thin Binary')
} || app.build_phases.length, embed)

# --- App Group on the app side too -------------------------------------------
app.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
end
runner_group = project.main_group['Runner']
unless runner_group.files.any? { |f| f.path == 'Runner.entitlements' }
  runner_group.new_reference('Runner.entitlements')
end

project.save
puts "ok: #{TARGET} (#{WIDGET_ID}) added to #{project.targets.map(&:name).join(', ')}"
