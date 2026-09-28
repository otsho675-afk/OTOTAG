require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target_name = 'RepairLiveActivity'

# Target zaten eklenmişse tekrar ekleme
if project.targets.any? { |t| t.name == target_name }
  puts "Target #{target_name} zaten eklenmiş, işlem atlandı."
  exit 0
end

runner_target = project.targets.find { |t| t.name == 'Runner' }
unless runner_target
  puts "Runner target bulunamadı!"
  exit 1
end

# 1. Yeni Widget Extension Target oluştur
widget_target = project.new_target(:app_extension, target_name, :ios, '16.2')

# 2. Derleme ayarlarını ata
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = target_name
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.oto.tag.RepairLiveActivity'
  config.build_settings['INFOPLIST_FILE'] = 'RepairLiveActivity/Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RepairLiveActivity/RepairLiveActivity.entitlements'
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

# 4. Runner Target bağımlılığı ekle ve Widget'ı ana uygulamaya göm (Embed)
runner_target.add_dependency(widget_target)

embed_phase = runner_target.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' }
unless embed_phase
  embed_phase = runner_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_phase.dst_subfolder_spec = '13'
end

file_ref = embed_phase.add_file_reference(widget_target.product_reference)
file_ref.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 5. Projeyi kaydet
project.save
puts "Tebrikler! #{target_name} hedefi Runner.xcodeproj dosyasına başarıyla işlendi."