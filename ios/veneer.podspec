#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint veneer.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'veneer'
  s.version          = '0.9.1'
  s.summary          = 'Real native iOS 26 UI for Flutter: Liquid Glass, UIKit bars, composers and sheets.'
  s.description      = <<-DESC
One native overlay above the Flutter surface, driven by Flutter layout every frame: UIKit tab
and navigation bars, native composers and sheets, and Liquid Glass that refracts Flutter content.
                       DESC
  s.homepage         = 'https://github.com/troyvnit/veneer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Troy Lee' => 'troylee.it@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'veneer/Sources/veneer/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'veneer_privacy' => ['veneer/Sources/veneer/PrivacyInfo.xcprivacy']}
end
