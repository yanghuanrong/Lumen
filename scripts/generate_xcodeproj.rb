#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 生成 Peek.xcodeproj —— 让项目能在 Xcode 里直接打开、断点调试、查看视图层级。
#
# 为什么要生成工程而不是直接打开 Package.swift：
#   1. SPM 包在 Xcode 里调试会触发包依赖解析，本机沙箱环境下容易失败；
#   2. 生成工程后可以配置 Info.plist（LSUIElement 等）、Scheme、编译参数，
#      Xcode 里的运行/调试体验与打包产物一致。
#
# 用法： ruby scripts/generate_xcodeproj.rb
# 生成后： open Peek.xcodeproj

require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'Peek.xcodeproj')
TARGET_NAME = 'Peek'
BUNDLE_ID = 'com.peek.translate'
DEPLOYMENT_TARGET = '13.0'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

# ---------------------------------------------------------------- 目标
target = project.new_target(
  :application,
  TARGET_NAME,
  :osx,
  DEPLOYMENT_TARGET
)

# ---------------------------------------------------------------- 源文件
sources_root = File.join(ROOT, 'Sources', TARGET_NAME)
swift_files = Dir.glob(File.join(sources_root, '**', '*.swift')).sort

group = project.new_group(TARGET_NAME, 'Sources/Peek')
swift_files.each do |path|
  ref = group.new_reference(path)
  target.add_file_references([ref])
end

puts "✅ 已加入 #{swift_files.size} 个 Swift 文件"

# ---------------------------------------------------------------- Info.plist
# 直接写 XML，避免依赖 CFPropertyList / plist gem
info_plist_path = File.join(ROOT, 'Resources', 'Info.plist')
FileUtils.mkdir_p(File.dirname(info_plist_path))

File.write(info_plist_path, <<~PLIST)
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleName</key>                    <string>#{TARGET_NAME}</string>
      <key>CFBundleDisplayName</key>             <string>#{TARGET_NAME}</string>
      <key>CFBundleIdentifier</key>              <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
      <key>CFBundleExecutable</key>              <string>$(EXECUTABLE_NAME)</string>
      <key>CFBundlePackageType</key>             <string>APPL</string>
      <key>CFBundleShortVersionString</key>      <string>0.1.0</string>
      <key>CFBundleVersion</key>                 <string>0.1.0</string>
      <key>CFBundleIconFile</key>                <string>AppIcon</string>
      <key>LSMinimumSystemVersion</key>          <string>#{DEPLOYMENT_TARGET}</string>
      <key>NSHighResolutionCapable</key>         <true/>
      <!-- 无 Dock 图标，仅菜单栏 + 浮动面板 -->
      <key>LSUIElement</key>                     <true/>
      <key>NSHumanReadableCopyright</key>        <string>Peek · 个人划词翻译工具</string>
  </dict>
  </plist>
PLIST
puts "✅ 已生成 Resources/Info.plist"

# ---------------------------------------------------------------- 构建配置
project.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'INFOPLIST_FILE' => 'Resources/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'MACOSX_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'SWIFT_VERSION' => '5.0',
    'CODE_SIGN_IDENTITY' => '-',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGNING_REQUIRED' => 'NO',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'ENABLE_HARDENED_RUNTIME' => 'NO',
    'ALWAYS_SEARCH_USER_PATHS' => 'NO',
    'SWIFT_TREAT_WARNINGS_AS_ERRORS' => 'NO',
    # 调试时输出更完整
    'SWIFT_OPTIMIZATION_LEVEL' => config.name == 'Debug' ? '-Onone' : '-O',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => config.name == 'Debug' ? 'DEBUG' : '',
    'GCC_OPTIMIZATION_LEVEL' => config.name == 'Debug' ? '0' : 's',
    'ONLY_ACTIVE_ARCH' => config.name == 'Debug' ? 'YES' : 'NO',
    'ENABLE_TESTABILITY' => config.name == 'Debug' ? 'YES' : 'NO',
    # AppKit 应用
    'COMBINE_HIDPI_IMAGES' => 'YES'
  )
end

target.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'INFOPLIST_FILE' => 'Resources/Info.plist',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'CODE_SIGN_IDENTITY' => '-',
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGNING_REQUIRED' => 'NO',
    'CODE_SIGNING_ALLOWED' => 'NO',
    'ENABLE_HARDENED_RUNTIME' => 'NO'
  )
end

# ---------------------------------------------------------------- Scheme
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
# 调试时默认选中 Peek scheme
scheme.launch_action.build_configuration = 'Debug'
scheme.test_action.build_configuration = 'Debug'

scheme.save_as(PROJECT_PATH, TARGET_NAME, true)
puts "✅ 已创建 Scheme: #{TARGET_NAME}"

puts ""
puts "🎉 工程生成完毕：#{PROJECT_PATH}"
puts ""
puts "在 Xcode 中打开："
puts "  open #{PROJECT_PATH}"
