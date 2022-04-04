# frozen_string_literal: true

# Original code by MSP-Greg
# This script creates a 7z file using `vcpkg export` for use with Ruby mswin
# builds in GitHub Actions.

require 'fileutils'
require_relative 'common'

module CreateMswin
  class << self

    include Common

    PACKAGES = 'libffi libyaml openssl readline zlib'
    PKG_DEPENDS = 'vcpkg-cmake vcpkg-cmake-config'

    PKG_NAME = 'mswin'

    EXPORT_DIR = "#{TEMP}".gsub "\\", '/'

    VCPKG = ENV.fetch 'VCPKG_INSTALLATION_ROOT', 'C:/vcpkg'

    OPENSSL_PKG = 'packages/openssl_x64-windows'

    def generate_package_files
      ENV['VCPKG_ROOT'] = VCPKG

      Dir.chdir VCPKG do |d|
        update_info = %x(./vcpkg update)
        if update_info.include? 'No packages need updating'
          STDOUT.syswrite "\n#{GRN}No packages need updating#{RST}\n\n"
          exit 0
        else
          STDOUT.syswrite "\n#{YEL}#{LINE} Updates needed#{RST}\n#{update_info}"
        end

        exec_check "Upgrading #{PACKAGES}",
          "./vcpkg upgrade #{PACKAGES} #{PKG_DEPENDS} --triplet=x64-windows --no-dry-run"

        exec_check "Removing outdated packages",
          "./vcpkg remove --outdated"

        exec_check "Exporting package files from vcpkg",
          "./vcpkg export --triplet=x64-windows #{PACKAGES} --raw --output=#{PKG_NAME} --output-dir=#{EXPORT_DIR}"
      end

      # Locations for vcpkg OpenSSL build
      # X509::DEFAULT_CERT_FILE      C:\vcpkg\packages\openssl_x64-windows/cert.pem
      # X509::DEFAULT_CERT_DIR       C:\vcpkg\packages\openssl_x64-windows/certs
      # Config::DEFAULT_CONFIG_FILE  C:\vcpkg\packages\openssl_x64-windows/openssl.cnf

      # make certs dir and copy openssl.cnf file
      ssl_path = "#{EXPORT_DIR}/#{PKG_NAME}/#{OPENSSL_PKG}"
      FileUtils.mkdir_p "#{ssl_path}/certs"

      vcpkg_u = VCPKG.gsub "\\", '/'

      cnf_path = "#{vcpkg_u}/installed/x64-windows/tools/openssl/openssl.cnf"
      if File.readable? cnf_path
        IO.copy_stream cnf_path, "#{ssl_path}/openssl.cnf"
      end

      # vcpkg/installed/status contains a list of installed packages
      status_path = 'installed/vcpkg/status'
      IO.copy_stream "#{vcpkg_u}/#{status_path}", "#{EXPORT_DIR}/#{PKG_NAME}/#{status_path}"
    end

    def run
      generate_package_files

      # create 7z archive file
      tar_path = "#{__dir__}\\#{PKG_NAME}.7z".gsub '/', '\\'

      Dir.chdir("#{EXPORT_DIR}/#{PKG_NAME}") do
        exec_check "Creating 7z file", "\"#{SEVEN}\" a #{tar_path}"
      end

      time = Time.now.utc.strftime '%Y-%m-%d %H:%M:%S UTC'
      upload_7z_update PKG_NAME, time
    end
  end
end

CreateMswin.run
