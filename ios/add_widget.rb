require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target_name = 'RepairLiveActivity'

# Varsa eski hedefi temizleyip sıfırdan hatasız kuralım
existing_target = project.targets.find { |t| t.name == target_name }
if existing_target
  project.targets.delete(existing_target)
end

runner_target = project.targets.find { |t| t.name == 'Runner' }
unless runner_target
  puts "Runner target bulunamadı!"
  exit 1
end

# Runner'ın geliştirici takım kimliğini (Team ID) al
runner_team = runner_target.build_configurations.first.build_settings['DEVELOPMENT_TEAM']
runner_code_sign = runner_target.build_configurations.first.build_settings['CODE_SIGN_STYLE'] || 'Automatic'

# 1. Yeni Widget Extension Target oluştur
widget_target = project.new_target(:app_extension, target_name, :ios, '16.2')

# 2. Derleme ayarlarını ata
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = target_name
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.oto.tag.RepairLiveActivity'
  config.build_settings['INFOPLIST_FILE'] = 'RepairLiveActivity/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RepairLiveActivity/RepairLiveActivity.entitlements'
  config.build_settings['DEVELOPMENT_TEAM'] = runner_team if runner_team
  config.build_settings['CODE_SIGN_STYLE'] = runner_code_sign
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.2'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
end

# 3. Dosyaları gruba ekle ve Target ile bağla
group = project.main_group.find_subpath(target_name, true)
group.set_source_tree('SOURCE_ROOT')

swift_file = group.new_file('RepairLiveActivity/RepairLiveActivity.swift')
widget_target.add_file_references([swift_file])

# Assets varsa ekle
assets_path = 'RepairLiveActivity/Assets.xcassets'
if File.exist?(File.join('ios', assets_path))
  assets_file = group.new_file(assets_path)
  widget_target.resources_build_phase.add_file_reference(assets_file)
end

# 4. Runner Target bağımlılığı ekle
runner_target.add_dependency(widget_target)

# Varsa eski hatalı embed fazını kaldır
runner_target.copy_files_build_phases.each do |p|
  if p.dst_subfolder_spec == '13' && p.name == 'Embed Foundation Extensions'
    runner_target.build_phases.delete(p)
  end
end

# Yeni Embed fazı oluştur
embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.dst_subfolder_spec = '13'
file_ref = embed_phase.add_file_reference(widget_target.product_reference)
file_ref.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy'] }

# 5. KRİTİK ADIM (Cycle Hatasını Önleme):
# Embed fazını Flutter/CocoaPods Run Script aşamalarından ÖNCEYE taşı
runner_target.build_phases.delete(embed_phase)
first_script_idx = runner_target.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) }

if first_script_idx
  runner_target.build_phases.insert(first_script_idx, embed_phase)
else
  runner_target.build_phases << embed_phase
end

# 6. Projeyi kaydet
project.save
puts "Tebrikler! #{target_name} hedefi ve derleme sıralaması başarıyla optimize edildi."