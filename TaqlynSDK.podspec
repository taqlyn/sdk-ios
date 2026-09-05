Pod::Spec.new do |s|
  s.name             = 'TaqlynSDK'
  s.version          = '0.1.0'
  s.summary          = 'Taqlyn iOS SDK for universal and deferred deep linking'
  s.description      = <<-DESC
Taqlyn iOS SDK provides unified deep link routing, deferred deep linking with
privacy-first fallbacks, shortlink creation, and claim resolution for iOS 16+.
                       DESC
  s.homepage         = 'https://taqlyn.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Taqlyn' => 'dev@taqlyn.com' }
  s.source           = { :git => 'https://github.com/taqlyn/sdk-ios.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '16.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/TaqlynSDK/**/*.{swift}'
  s.resource_bundles = {
    'TaqlynSDK_Privacy' => ['Sources/TaqlynSDK/PrivacyInfo.xcprivacy']
  }

  s.frameworks       = 'Foundation', 'UIKit'
end
