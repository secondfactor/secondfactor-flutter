Pod::Spec.new do |s|
  s.name             = 'secondfactor'
  s.version          = '0.1.0'
  s.summary          = 'secondfactor.ai hosted phone verification for Flutter.'
  s.description      = 'Opens the secondfactor.ai hosted verification page and reads the result when the user comes back.'
  s.homepage         = 'https://secondfactor.ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Lambda Payments'
  s.source           = { :path => '.' }
  s.source_files     = 'secondfactor/Sources/secondfactor/**/*.swift'
  s.dependency 'Flutter'
  # The plugin builds for iOS 13, so apps keep their own minimum. Verification
  # itself needs iOS 17.4, which is checked when it is called.
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
