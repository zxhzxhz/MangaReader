platform :ios, '18.0'

install! 'cocoapods', :deterministic_uuids => false
use_frameworks!

target 'MangaReader' do
  pod 'onnxruntime-objc', '~> 1.20'
  pod 'UnrarKit', '~> 2.10'
  pod 'TOCropViewController', '~> 2.6'
  pod 'libwebp', '~> 1.3'
end

target 'MangaReaderTests' do
  inherit! :search_paths
end
