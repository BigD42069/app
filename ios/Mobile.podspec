Pod::Spec.new do |s|
  s.name             = 'Mobile'
  s.version          = '1.0.0'
  s.summary          = 'Gomobile tachograph parser bindings'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'Proprietary', :text => 'Provided with app bundle' }
  s.author           = { 'App' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.vendored_frameworks = 'Frameworks/Mobile.xcframework'
  s.requires_arc     = true
end
