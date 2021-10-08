# frozen_string_literal: true

# Original code by MSP-Greg
# This script creates 7z files of the mingw64 and ucrt64 MSYS2 gcc tool chains
# for use with GitHub Actions.  Since these files are installed on the Actions
# Windows runner's hard drive, smaller zip files speed up the installation.
# Hence, many of the 'doc' related files in the 'share' folder are removed.

require 'fileutils'

module CreateMingwGCC
  class << self

    MSYS2_ROOT = "C:/msys64"
    TEMP = ENV.fetch('RUNNER_TEMP') { ENV.fetch('RUNNER_WORKSPACE') { ENV['TEMP'] } }
    TAR_DIR = "#{TEMP}/msys64"

    SYNC  = 'var/lib/pacman/sync'
    LOCAL = 'var/lib/pacman/local'

    SEVEN = "C:\\Program Files\\7-Zip\\7z"

    DASH  = ENV['GITHUB_ACTIONS'] ? "\u2500".dup.force_encoding('utf-8') : 151.chr
    LINE  = DASH * 40
    GRN   = "\e[92m"
    YEL   = "\e[93m"
    RST   = "\e[0m"

    def install_gcc
      args = '--noconfirm --noprogressbar --needed'
      # zlib required by gcc
      base_gcc  = %w[dlfcn make pkgconf libmangle-git tools-git gcc]
      base_ruby = %w[gmp libffi libyaml openssl ragel readline]
      pkgs = (base_gcc + base_ruby).unshift('').join " #{@pkg_pre}"

      Dir.chdir("#{MSYS2_ROOT}/usr/bin") do
        exit(1) unless system "sed -i 's/^CheckSpace/#CheckSpace/g' C:/msys64/etc/pacman.conf"

        STDOUT.syswrite "\n#{YEL}#{LINE} Updating all installed packages#{RST}\n"
        exit(1) unless system "#{MSYS2_ROOT}/usr/bin/pacman.exe -Syuu  --noconfirm'"
        system 'taskkill /f /fi "MODULES eq msys-2.0.dll"'

        STDOUT.syswrite "\n#{YEL}#{LINE} Updating all installed packages (2nd pass)#{RST}\n"
        exit(1) unless system "#{MSYS2_ROOT}/usr/bin/pacman.exe -Syuu  --noconfirm'"
        system 'taskkill /f /fi "MODULES eq msys-2.0.dll"'

        STDOUT.syswrite "\n#{YEL}#{LINE} Updating the following #{@pkg_pre[0..-2]} packages:#{RST}\n" \
          "#{YEL}#{(base_gcc + base_ruby).join ' '}#{RST}\n\n"
        exit(1) unless system "#{MSYS2_ROOT}/usr/bin/pacman.exe -S #{args} #{pkgs}"
      end
    end

    def run
      case ARGV[0].downcase
      when 'ucrt64'
        @pkg_name = 'ucrt64'  ; @pkg_pre = 'mingw-w64-ucrt-x86_64-'
      when 'mingw64'
        @pkg_name = 'mingw64' ; @pkg_pre = 'mingw-w64-x86_64-'
      when 'mingw32'
        @pkg_name = 'mingw32' ; @pkg_pre = 'mingw-w64-i686-'
      else
        puts 'Invalid package type, must be ucrt64, mingw64, or mingw32'
        exit 1
      end

      current_pkgs = %x[#{MSYS2_ROOT}/usr/bin/pacman.exe -Q]
        .lines.select { |l| l.start_with? @pkg_pre }.join

      install_gcc

      updated_pkgs = %x[#{MSYS2_ROOT}/usr/bin/pacman.exe -Q]
        .lines.select { |l| l.start_with? @pkg_pre }

      array_2_column updated_pkgs.map { |el| el.strip.gsub @pkg_pre, ''}, 48,
        "Installed #{@pkg_pre[0..-2]} Packages"

      if current_pkgs == updated_pkgs.join
        File.write ENV['GITHUB_ENV'], "Create7z=no\n", mode: 'a'
        STDOUT.syswrite "\n** No update to #{@pkg_name} gcc tools needed **\n\n"
        exit 0
      else
        File.write ENV['GITHUB_ENV'], "Create7z=yes\n", mode: 'a'
        STDOUT.syswrite "\n#{GRN}** Creating and Uploading #{@pkg_name} gcc tools 7z **#{RST}\n\n"
      end

      Dir.chdir(TEMP) do
        FileUtils.mkdir_p "msys64/#{SYNC}"
        FileUtils.mkdir_p "msys64/#{LOCAL}"
      end

      Dir.chdir "#{MSYS2_ROOT}/var/lib/pacman/sync" do
        FileUtils.cp "#{@pkg_name}.db", "#{TAR_DIR}/#{SYNC}"
        FileUtils.cp "#{@pkg_name}.db.sig", "#{TAR_DIR}/#{SYNC}"
      end

      ary = Dir.glob "#{@pkg_pre}*", base: "#{MSYS2_ROOT}/#{LOCAL}"

      local = "#{TAR_DIR}/#{LOCAL}"

      Dir.chdir "#{MSYS2_ROOT}/#{LOCAL}" do
        ary.each { |dir| FileUtils.copy_entry dir, "#{local}/#{dir}" }
      end

      FileUtils.copy_entry "#{MSYS2_ROOT}/#{@pkg_name}", "#{TAR_DIR}/#{@pkg_name}"

      Dir.chdir "#{TAR_DIR}/#{@pkg_name}/share/doc" do
        ary = Dir.glob "*"
        ary.each { |dir| FileUtils.remove_dir dir }
      end

      Dir.chdir "#{TAR_DIR}/#{@pkg_name}/share/info" do
        ary = Dir.glob "*.gz"
        ary.each { |file| FileUtils.remove_file file }
      end

      Dir.chdir "#{TAR_DIR}/#{@pkg_name}/share/man" do
        ary = Dir.glob "**/*.gz"
        ary.each { |file| FileUtils.remove_file file }
      end

      Dir.chdir "#{TAR_DIR}/#{LOCAL}" do
        ary = Dir.glob "#{@pkg_pre}*/files"
        ary.each do |fn|
          File.open(fn, mode: 'r+b') { |f|
            str = f.read
            f.truncate 0
            f.rewind
            str.gsub!(/^#{@pkg_name}\/share\/doc\/\S+\s*/m , '')
            str.gsub!(/^#{@pkg_name}\/share\/info\/\S+\s*/m, '')
            str.gsub!(/^#{@pkg_name}\/share\/man\/\S+\s*/m , '')
            f.write "#{str.strip}\n\n"
          }
        end
      end

      # create 7z file
      tar_path = "#{Dir.pwd}\\#{@pkg_name}.7z".gsub '/', '\\'
      Dir.chdir TAR_DIR do
        system "\"#{SEVEN}\" a #{tar_path}"
      end
    end

    def array_2_column(ary, wid, hdr)
      pad = (wid - hdr.length - 5)/2

      hdr_pad = pad > 0 ? "#{DASH * pad} #{hdr} #{DASH * pad}" : hdr

      STDOUT.syswrite "\n#{YEL}#{hdr_pad.ljust wid}#{hdr_pad}#{RST}\n"

      mod = ary.length % 2
      split  = ary.length/2
      offset = split + mod
      (0...split).each do
        |i| STDOUT.syswrite "#{ary[i].ljust wid}#{ary[i + offset]}\n"
      end
      STDOUT.syswrite "#{ary[split]}\n" if mod == 1
    end
  end
end

CreateMingwGCC.run
