# frozen_string_literal: true

# Original code by MSP-Greg
# This script creates a 7z file using `vcpkg export` for use with Ruby mswin
# builds in GitHub Actions.

require 'fileutils'
require_relative 'common'

module CreateMswin
  class << self

    include Common

    PACKAGES = 'pkgconf gmp libffi libyaml openssl readline-win32 zlib'
    PKG_DEPENDS = 'vcpkg-cmake vcpkg-cmake-config vcpkg-cmake-get-vars vcpkg-tool-meson'

    PKG_NAME = 'mswin'

    EXPORT_DIR = "#{TEMP}".gsub "\\", '/'

    VCPKG = ENV.fetch 'VCPKG_INSTALLATION_ROOT', 'C:/vcpkg'

    OPENSSL_PKG = 'packages/openssl_x64-windows'

    def copy_ssl_files
      # Locations for vcpkg OpenSSL build
      # X509::DEFAULT_CERT_FILE      C:\vcpkg\packages\openssl_x64-windows/cert.pem
      # X509::DEFAULT_CERT_DIR       C:\vcpkg\packages\openssl_x64-windows/certs
      # Config::DEFAULT_CONFIG_FILE  C:\vcpkg\packages\openssl_x64-windows/openssl.cnf

      vcpkg_u = VCPKG.gsub "\\", '/'

      # make certs dir
      export_ssl_path = "#{EXPORT_DIR}/#{PKG_NAME}/#{OPENSSL_PKG}"
      FileUtils.mkdir_p "#{export_ssl_path}/certs"

      # updating OpenSSL package may overwrite cert.pem
      cert_path = "#{RbConfig::TOPDIR}/ssl/cert.pem"

      if File.readable? cert_path
        vcpkg_ssl_path = "#{vcpkg_u}/#{OPENSSL_PKG}"
        unless Dir.exist? vcpkg_ssl_path
          FileUtils.mkdir_p vcpkg_ssl_path
        end
        IO.copy_stream cert_path, "#{vcpkg_ssl_path}/cert.pem"
        IO.copy_stream cert_path, "#{export_ssl_path}/cert.pem"
      end

      # copy openssl.cnf file
      conf_path = "#{vcpkg_u}/installed/x64-windows/tools/openssl/openssl.cnf"
      if File.readable? conf_path
        IO.copy_stream conf_path, "#{export_ssl_path}/openssl.cnf"
      end
    end

    def generate_package_files
      ENV['VCPKG_ROOT'] = VCPKG

      Dir.chdir VCPKG do |d|

        install_info = %x(./vcpkg install  #{PACKAGES} --triplet=x64-windows --dry-run)
        
        installed_packages = install_info.include?('The following packages will be built and installed')

        exec_check "Installing #{PACKAGES}",
          "./vcpkg install #{PACKAGES} --triplet=x64-windows"

        update_info = %x(./vcpkg update)
        if !installed_packages && update_info.include?('No packages need updating') && !ENV.key?('FORCE_UPDATE')
          STDOUT.syswrite "\n#{GRN}No packages need updating#{RST}\n\n"
          exit 0
        else
          STDOUT.syswrite "\n#{YEL}#{LINE} Updates needed#{RST}\n#{update_info}"
        end

        exec_check "Upgrading #{PACKAGES}",
          "./vcpkg upgrade #{PACKAGES} #{PKG_DEPENDS} --triplet=x64-windows --no-dry-run"

        exec_check "Removing outdated packages",
          "./vcpkg remove --outdated --recurse"

        exec_check "Package List",
          "./vcpkg list"

        exec_check "Exporting package files from vcpkg",
          "./vcpkg export --triplet=x64-windows #{PACKAGES} --raw --output=#{PKG_NAME} --output-dir=#{EXPORT_DIR}"
      end

      # remove tracked files
      Dir.chdir "#{EXPORT_DIR}/#{PKG_NAME}" do
        FileUtils.remove_dir 'scripts', true
      end

      vcpkg_u = VCPKG.gsub "\\", '/'

      # vcpkg/installed/status contains a list of installed packages
      status_path = 'installed/vcpkg/status'
      IO.copy_stream "#{vcpkg_u}/#{status_path}", "#{EXPORT_DIR}/#{PKG_NAME}/#{status_path}"
    end

    def run
      generate_package_files
      
      copy_ssl_files

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
