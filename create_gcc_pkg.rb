# frozen_string_literal: true

# Original code by MSP-Greg
# This script creates 7z files of the mingw64 and ucrt64 MSYS2 gcc tool chains
# for use with GitHub Actions.  Since these files are installed on the Actions
# Windows runner's hard drive, smaller zip files speed up the installation.
# Hence, many of the 'doc' related files in the 'share' folder are removed.

# OpenSSL - There are comments and code lines that are commented out.  The archives
# may need to have one version of OpenSSL fully installed, and if that version
# differs from the current MSYS2 version, the OpenSSL files needed to run (not build)
# the MSYS2 utilities need to remain.  They should be from the most recent version
# that MSYS2 uses.
#
# This means there are files that are not associated with an installed package,
# so the code gets more complex, and some code is just needed for the transition.

require 'fileutils'
require_relative 'common'

module CreateMingwGCC
  class << self

    include Common

    TAR_DIR = "#{TEMP}/msys64"

    SYNC  = 'var/lib/pacman/sync'
    LOCAL = 'var/lib/pacman/local'

    PKG_NAME = ARGV[0].downcase

    PKG_DIR, PKG_PRE =
      case PKG_NAME[/\A[^-]+/]
      when 'ucrt64'
        ['ucrt64', 'mingw-w64-ucrt-x86_64-']
      when 'mingw64'
        ['mingw64', 'mingw-w64-x86_64-']
      when 'mingw32'
        ['mingw32', 'mingw-w64-i686-']
      else
        STDOUT.syswrite "Invalid package type, must be ucrt64, mingw64, or mingw32\n"
        exit 1
      end

    MSYS2_PKG = "#{MSYS2_ROOT}/#{PKG_DIR}"
    
    SSL_1_DLLS = %w[bin/libcrypto-1_1-x64.dll bin/libssl-1_1-x64.dll]

    def add_ri2_key
      # appveyor ri2 package signing key
      key = 'F98B8484BE8BF1C5'
      exec_check "pacman-key --init", "bash.exe -c \"pacman-key --init\""
      exec_check "Get RI2 Key" , "bash.exe -c \"pacman-key --recv-keys #{key}\""
      exec_check "Sign RI2 Key", "bash.exe -c \"pacman-key --lsign-key #{key}\""
    end

    def openssl_downgrade
      add_ri2_key

      pkg_name = "openssl-1.1.1.t-1-any.pkg.tar.zst"
      pkg = "https://github.com/ruby/setup-msys2-gcc/releases/download/msys2-packages/#{PKG_PRE}#{pkg_name}"
      pkg_sig = "#{pkg}.sig"

      # save previous dll files so we can copy back into folder
      SSL_3_SAVE_FILES.each { |fn| FileUtils.cp "#{MSYS2_PKG}/#{fn}", "." }

      download pkg    , "./#{PKG_PRE}#{pkg_name}"
      download pkg_sig, "./#{PKG_PRE}#{pkg_name}.sig"

      # install package
      exec_check "Install OpenSSL Downgrade", "pacman.exe -Udd --noconfirm --noprogressbar #{PKG_PRE}#{pkg_name}"

      # copy previous dlls back into MSYS2 folder
      SSL_3_SAVE_FILES.each { |fn| FileUtils.cp_r File.basename(fn) , "#{MSYS2_PKG}/#{fn}" }
      openssl_copy_cert_files
    end

    # as of Jan-2023, not used, save for future use
    def openssl_upgrade
      add_ri2_key

      pkg_name = "openssl-3.0.7-1-any.pkg.tar.zst"
      pkg = "https://github.com/oneclick/rubyinstaller2-packages/releases/download/ci.ri2/#{PKG_PRE}#{pkg_name}"
      pkg_sig = "#{pkg}.sig"
      old_dlls = %w[libcrypto-1_1-x64.dll libssl-1_1-x64.dll]
      dll_root = "#{MSYS2_ROOT}/#{PKG_DIR}/bin"

      # save previous dll files so we can copy back into folder
      old_dlls.each { |fn| FileUtils.cp "#{dll_root}/#{fn}", "." }

      download pkg    , "./#{PKG_PRE}#{pkg_name}"
      download pkg_sig, "./#{PKG_PRE}#{pkg_name}.sig"

      # install package
      exec_check "Install OpenSSL Upgrade", "pacman.exe -Udd --noconfirm --noprogressbar #{PKG_PRE}#{pkg_name}"

      # copy previous dlls back into MSYS2 folder
      old_dlls.each do |fn|
        unless File.exist? "#{dll_root}/#{fn}"
          FileUtils.cp fn , "#{dll_root}/#{fn}"
        end
      end
    end

    # Below files are part of the 'ca-certificates' package, they are not
    # included in the openssl package
    # This is needed due to MSYS2 OpenSSL 1.1.1 using 'ssl', and the 3.0 version
    # using 'etc/ssl'.
    def openssl_copy_cert_files
      new_dir = "#{MSYS2_PKG}/ssl"
      old_dir = "#{MSYS2_PKG}/etc/ssl"
      unless Dir.exist? "#{new_dir}/certs"
        FileUtils.mkdir_p "#{new_dir}/certs"
      end
      %w[cert.pem certs/ca-bundle.crt certs/ca-bundle.trust.crt].each do |fn|
        if File.exist?("#{old_dir}/#{fn}") && !File.exist?("#{new_dir}/#{fn}")
          FileUtils.cp "#{old_dir}/#{fn}", "#{new_dir}/#{fn}"
        end
      end
    end

    def install_gcc
      args = '--noconfirm --noprogressbar --needed'
      # zlib required by gcc, gdbm for older Rubies
      base_gcc  = %w[make pkgconf libmangle-git tools-git gcc curl]
      base_ruby = PKG_NAME.end_with?('-3.0') ?
        %w[gdbm gmp libffi libyaml openssl ragel readline] :
        %w[gdbm gmp libffi libyaml openssl ragel readline]

      pkgs = (base_gcc + base_ruby).unshift('').join " #{PKG_PRE}"

      unless PKG_NAME.end_with? '-3.0'
        SSL_3_SAVE_FILES.each do |fn|
          FileUtils.remove_file "#{MSYS2_PKG}/#{fn}" if File.exist? "#{MSYS2_PKG}/#{fn}"
        end
      end

      # May not be needed, but...
      # Note that OpenSSL may need to be ignored
      if PKG_NAME.end_with?('-3.0')
        pacman_syuu
     else
        pacman_syuu
      end

      exec_check "Updating the following #{PKG_PRE[0..-2]} packages:#{RST}\n" \
        "#{YEL}#{(base_gcc + base_ruby).join ' '}",
        "#{PACMAN} -S #{args} #{pkgs}"

      if PKG_NAME.end_with? '-3.0'
        SSL_1_DLLS.each do |fn|
          FileUtils.remove_file("#{MSYS2_PKG}/#{fn}") if File.exist?("#{MSYS2_PKG}/#{fn}")
        end
      else
        openssl_downgrade
      end
    end

    # copies needed files from C:/msys64 to TEMP
    def copy_to_temp
      Dir.chdir TEMP do
        FileUtils.mkdir_p "msys64/#{SYNC}"
        FileUtils.mkdir_p "msys64/#{LOCAL}"
      end

      Dir.chdir "#{MSYS2_ROOT}/#{SYNC}" do
        FileUtils.cp "#{PKG_DIR}.db", "#{TAR_DIR}/#{SYNC}"
        FileUtils.cp "#{PKG_DIR}.db.sig", "#{TAR_DIR}/#{SYNC}"
      end

      ary = Dir.glob "#{PKG_PRE}*", base: "#{MSYS2_ROOT}/#{LOCAL}"

      local = "#{TAR_DIR}/#{LOCAL}"

      Dir.chdir "#{MSYS2_ROOT}/#{LOCAL}" do
        ary.each { |dir| FileUtils.copy_entry dir, "#{local}/#{dir}" }
      end

      FileUtils.copy_entry "#{MSYS2_ROOT}/#{PKG_DIR}", "#{TAR_DIR}/#{PKG_DIR}"
    end

    # removes files contained in 'share' folder to reduce 7z file size
    def clean_package
      share = "#{TAR_DIR}/#{PKG_DIR}/share"

      Dir.chdir "#{share}/doc" do
        ary = Dir.glob "*"
        ary.each { |dir| FileUtils.remove_dir dir }
      end

      Dir.chdir "#{share}/info" do
        ary = Dir.glob "*.gz"
        ary.each { |file| FileUtils.remove_file file }
      end

      Dir.chdir "#{share}/man" do
        ary = Dir.glob "**/*.gz"
        ary.each { |file| FileUtils.remove_file file }
      end

      # remove entries in 'files' file so updates won't log warnings
      Dir.chdir "#{TAR_DIR}/#{LOCAL}" do
        ary = Dir.glob "#{PKG_PRE}*/files"
        ary.each do |fn|
          File.open(fn, mode: 'r+b') { |f|
            str = f.read
            f.truncate 0
            f.rewind
            str.gsub!(/^#{PKG_DIR}\/share\/doc\/\S+\s*/m , '')
            str.gsub!(/^#{PKG_DIR}\/share\/info\/\S+\s*/m, '')
            str.gsub!(/^#{PKG_DIR}\/share\/man\/\S+\s*/m , '')
            f.write "#{str.strip}\n\n"
          }
        end
      end
    end

    def run
      current_pkgs = %x[#{PACMAN} -Q].split("\n").select { |l| l.start_with? PKG_PRE }

      # exec_check "Removing #{PKG_PRE}dlfcn",
      #   "#{PACMAN} -R --noconfirm --noprogressbar #{PKG_PRE}dlfcn"

      install_gcc

      time = Time.now.utc.strftime '%Y-%m-%d %H:%M:%S UTC'

      updated_pkgs = %x[#{PACMAN} -Q].split("\n").select { |l| l.start_with? PKG_PRE }

      # log current packages
      log_array_2_column updated_pkgs.map { |el| el.sub PKG_PRE, ''}, 48,
        "Installed #{PKG_PRE[0..-2]} Packages"

      if (current_pkgs == updated_pkgs) && !ENV.key?('FORCE_UPDATE')
        STDOUT.syswrite "\n** No update to #{PKG_DIR} gcc tools needed **\n\n"
        exit 0
      else
        STDOUT.syswrite "\n#{GRN}** Creating and Uploading #{PKG_DIR} gcc tools 7z **#{RST}\n\n"
      end

      copy_to_temp

      clean_package

      # create 7z file
      STDOUT.syswrite "##[group]#{YEL}Create #{PKG_NAME} 7z file#{RST}\n"
      tar_path = "#{Dir.pwd}\\#{PKG_NAME}.7z".gsub '/', '\\'
      Dir.chdir TAR_DIR do
        exit 1 unless system "\"#{SEVEN}\" a #{tar_path}"
      end
      STDOUT.syswrite "##[endgroup]\n"

      upload_7z_update PKG_NAME, time
    end
  end
end

CreateMingwGCC.run
