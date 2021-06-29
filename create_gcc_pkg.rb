# frozen_string_literal: true

require 'fileutils'

module CreateMingwGCC
  class << self

    MSYS2_ROOT = "C:/msys64"
    TEMP = ENV.fetch('RUNNER_TEMP') { ENV.fetch('RUNNER_WORKSPACE') { ENV['TEMP'] } }
    TAR_DIR = "#{TEMP}/msys64"

    SYNC = 'var/lib/pacman/sync'
    LOCAL = 'var/lib/pacman/local'

    SEVEN = "C:\\Program Files\\7-Zip\\7z"

    def install_gcc
      args = '--noconfirm --noprogressbar --needed'
      pkgs = %w[dlfcn make pkgconf libyaml libmangle-git gcc].unshift('')
        .join " #{@pkg_pre}"
      Dir.chdir("#{MSYS2_ROOT}/usr/bin") do
        cmd = "sed -i 's/^CheckSpace/#CheckSpace/g' C:/msys64/etc/pacman.conf"
        system cmd
        cmd = "#{MSYS2_ROOT}/usr/bin/pacman.exe -Sy #{args} pacman-mirrors"
        system cmd
        cmd = "#{MSYS2_ROOT}/usr/bin/pacman.exe -S #{args} #{pkgs}"
        system cmd
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

      install_gcc

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

      # create 7z file
      tar_path = "#{Dir.pwd}\\#{@pkg_name}.7z".gsub '/', '\\'
      Dir.chdir TAR_DIR do
        system "\"#{SEVEN}\" a #{tar_path}"
      end
    end
  end
end

CreateMingwGCC.run
