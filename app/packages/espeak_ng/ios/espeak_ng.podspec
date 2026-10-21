# Compiles espeak-ng straight into the app binary. There is no framework and
# no plugin class: the Dart side resolves the symbols out of the process, so
# the only requirement is that the objects end up linked in.
Pod::Spec.new do |s|
  s.name             = 'espeak_ng'
  s.version          = '1.0.0'
  s.summary          = 'eSpeak-NG phonemizer for lingo_node.'
  s.description      = <<-DESC
  eSpeak-NG compiled for FFI, used only to turn text into IPA. GPL v3 --
  see LICENSE.md.
                       DESC
  s.homepage         = 'https://github.com/espeak-ng/espeak-ng'
  s.license          = { :type => 'GPL-3.0', :file => '../LICENSE.md' }
  s.author           = 'espeak-ng contributors'
  s.source           = { :path => '.' }

  espeak_dir = 'Classes/espeak_ng'

  s.source_files = ["#{espeak_dir}/**/*.c", "#{espeak_dir}/**/*.h"]
  # Only the bridge header is public; exposing the rest collides with other
  # pods that carry their own copies of common header names.
  s.public_header_files = ["#{espeak_dir}/include/espeak_bridge.h"]

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => [
      "$(PODS_TARGET_SRCROOT)/#{espeak_dir}/include",
      "$(PODS_TARGET_SRCROOT)/#{espeak_dir}/include/espeak-ng",
      "$(PODS_TARGET_SRCROOT)/#{espeak_dir}",
      "$(PODS_TARGET_SRCROOT)/#{espeak_dir}/ucd-include",
      "$(PODS_TARGET_SRCROOT)/#{espeak_dir}/include/ucd",
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      'HAVE_STDINT_H=1',
      'HAVE_MKSTEMP=1',
      'USE_ASYNC=0',
      'USE_KLATT=1',
      'USE_LIBPCAUDIO=0',
      'USE_LIBSONIC=0',
      'USE_MBROLA=0',
      'USE_SPEECHPLAYER=0',
      'PACKAGE_VERSION=\"1.52.0\"',
    ].join(' '),
    'OTHER_CFLAGS' => "-w -include $(PODS_TARGET_SRCROOT)/#{espeak_dir}/config.h",
  }

  s.dependency 'Flutter'
  s.platform = :ios, '16.0'
end
