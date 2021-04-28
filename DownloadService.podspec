#
# Be sure to run `pod lib lint DownloadService.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'DownloadService'
  s.version          = '0.1.1'
  s.summary          = 'Library to simplify download process'
  s.swift_versions   = '5.2'

  s.description      = <<-DESC
                        Library to simplify download process. You can use Downloadable protocol to make stuff downloadable :)
                       DESC

  s.homepage         = 'https://github.com/syrupmg/DownloadService'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = {
      'abesmon' => 'abesmon@gmail.com',
      'horovodovodo4ka' => 'xbitstream@gmail.com'
  }
  s.source           = { :git => 'https://github.com/syrupmg/DownloadService.git', :tag => s.version.to_s }

  s.ios.deployment_target = '8.0'
  s.tvos.deployment_target = '9.0'

  s.source_files = 'DownloadService/**/*.{swift}'

  s.dependency 'SMG-HWIFileDownload'
end
