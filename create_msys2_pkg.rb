# frozen_string_literal: true

require 'fileutils'

module CreateMSYS2Tools
  class << self

    MSYS2_ROOT = 'C:/msys64'
    TEMP = ENV.fetch('RUNNER_TEMP') { ENV.fetch('RUNNER_WORKSPACE') { ENV['TEMP'] } }
    ORIG_MSYS2 = "#{TEMP}/msys64".gsub '\\', '/'

    SYNC = 'var/lib/pacman/sync'
    LOCAL = 'var/lib/pacman/local'

    SEVEN = 'C:\Program Files\7-Zip\7z'

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
      puts "Removed #{removed_files} files"
    end

    # remove unneeded database files
    def clean_database(pre)
      dir = "#{MSYS2_ROOT}/#{SYNC}"
      files = Dir.glob('*', base: dir).reject { |fn| fn.start_with? pre }
      Dir.chdir(dir) do
        files.each { |fn| File.delete fn }
      end
    end

    def run
      remove_non_msys2

      remove_duplicate_files
      clean_database 'msys'

      # create 7z file
      tar_path = "#{Dir.pwd}\\msys2.7z".gsub '/', '\\'
      Dir.chdir MSYS2_ROOT do
        system "\"#{SEVEN}\" a #{tar_path}"
      end
    end
  end
end

CreateMSYS2Tools.run
