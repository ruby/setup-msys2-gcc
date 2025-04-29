# frozen_string_literal: true

# Original code by MSP-Greg
# This script creates a 7z file of the MSYS2 base tools (located in usr/bin)
# for use with GitHub Actions.  Since these files are installed on the Actions
# Windows runner's hard drive, smaller zip files speed up the installation.
# Hence, many of the 'doc' related files in the 'share' folder are removed.

require 'fileutils'
require_relative 'common'

module CreateMSYS2Tools
  class << self

    include Common

    TEMP = ENV.fetch('RUNNER_TEMP') { ENV.fetch('RUNNER_WORKSPACE') { ENV['TEMP'] } }
    ORIG_MSYS2 = "#{TEMP}/msys64".gsub '\\', '/'

    SYNC  = 'var/lib/pacman/sync'
    LOCAL = 'var/lib/pacman/local'
    CACHE = 'var/cache/pacman/pkg'

    MSYS2_PKG = case RUBY_PLATFORM
                when 'aarch64-mingw-ucrt'
                  "#{MSYS2_ROOT}/clangarm64"
                when /ucrt$/
                  "#{MSYS2_ROOT}/ucrt64"
                else
                  "#{MSYS2_ROOT}/mingw64"
                end

    PKG_NAME = ARGV[0].downcase

    SSL_3_SAVE_FILES = %w[
      bin/libcrypto-3-x64.dll
      bin/libssl-3-x64.dll
      etc/ssl/openssl.cnf
    ]

    def update_msys2

      SSL_3_SAVE_FILES.each do |fn|
        FileUtils.remove_file "#{MSYS2_PKG}/#{fn}" if File.exist? "#{MSYS2_PKG}/#{fn}"
      end

      updated_keys = pacman_syuu

      pkgs = 'autoconf-wrapper autogen automake-wrapper bison diffutils libtool m4 make patch re2c texinfo texinfo-tex compression'
      exec_check "Install MSYS2 Packages#{RST}\n#{YEL}#{pkgs}",
        "#{PACMAN} -S --noconfirm --needed --noprogressbar #{pkgs}"
      updated_keys
    end

    def remove_non_msys2
      dirs = %w[clang32 clang64 clangarm64 mingw32 mingw64 ucrt64]
      Dir.chdir MSYS2_ROOT do |d|
        dirs.each { |dir_name| FileUtils.rm_rf dir_name }
      end

      dir = "#{MSYS2_ROOT}/#{LOCAL}"
      Dir.chdir dir do |d|
        del_dirs = Dir['mingw*']
        del_dirs.each { |dir_name| FileUtils.rm_rf dir_name }
      end
    end

    # remove files from 7z that are identical to Windows image
    def remove_duplicate_files
      files = Dir.glob('**/*', base: MSYS2_ROOT).reject { |fn| fn.start_with? LOCAL }

      removed_files = 0

      Dir.chdir MSYS2_ROOT do |d|
        files.each do |fn|
          old_fn = "#{ORIG_MSYS2}/#{fn}"
          if File.exist?(old_fn) && File.mtime(fn) == File.mtime(old_fn)
            removed_files += 1
            File.delete fn
          end
        end
      end
      STDOUT.syswrite "Removed #{removed_files} files\n"
    end

    # remove unneeded database files
    def clean_database(pre)
      dir = "#{MSYS2_ROOT}/#{SYNC}"
      files = Dir.glob('*', base: dir).reject { |fn| fn.start_with? pre }
      Dir.chdir(dir) do
        files.each { |fn| File.delete fn }
      end
    end

    # remove downloaded packages and their '.sig' files
    def clean_packages
      dir = "#{MSYS2_ROOT}/#{CACHE}"
      files = Dir.glob('*.*', base: dir)
      Dir.chdir(dir) do
        files.each do |fn|
          next unless File.file? fn
          File.delete fn
        end
      end
    end

    def run
      current_pkgs = %x[#{PACMAN} -Q].split("\n").reject { |l| l.start_with? 'mingw-w64-' }

      updated_keys = update_msys2

      updated_pkgs = %x[#{PACMAN} -Q].split("\n").reject { |l| l.start_with? 'mingw-w64-' }

      time = Time.now.utc.strftime '%Y-%m-%d %H:%M:%S UTC'

      log_array_2_column updated_pkgs, 48, "Installed MSYS2 Packages"

      if current_pkgs == updated_pkgs && !updated_keys && !ENV.key?('FORCE_UPDATE')
        STDOUT.syswrite "\n** No update to MSYS2 tools needed **\n\n"
        exit 0
      else
        STDOUT.syswrite "\n#{GRN}** Creating and Uploading MSYS update 7z **#{RST}\n\n"
      end

      exec_check "Remove all uninstalled packages" , "#{BASH} -c \"paccache -r -f -u -k0\""
      exec_check "Keep the newest for all other packages" , "#{BASH} -c \"paccache -r -f -k1\""
      exec_check "Remove all cached packages" , "#{PACMAN} -Scc --noconfirm"

      remove_non_msys2
      remove_duplicate_files if File.exist?(ORIG_MSYS2)
      clean_database 'msys'
      clean_packages

      # create 7z file
      STDOUT.syswrite "##[group]#{YEL}Create msys2 7z file#{RST}\n"
      tar_path = "#{Dir.pwd}\\#{PKG_NAME}.7z".gsub '/', '\\'
      Dir.chdir MSYS2_ROOT do
        exit 1 unless system "\"#{SEVEN}\" a #{tar_path}"
      end
      STDOUT.syswrite "##[endgroup]\n"

      upload_7z_update PKG_NAME, time
    end
  end
end

CreateMSYS2Tools.run
