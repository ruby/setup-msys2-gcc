# frozen_string_literal: true

# 25-Dec-2022 Actions cron jobs stop if repo has no commits for 60 days.

require 'json'
require 'net/http'
require 'uri'

module Common
  # Generic constants
  USER_REPO    = ENV['GITHUB_REPOSITORY']
  TOKEN        = ENV['GITHUB_TOKEN']
  BUILD_NUMBER = ENV['GITHUB_RUN_NUMBER']

  GH_NAME   = "#{USER_REPO}-actions"
  GH_API    = 'api.github.com'
  GH_UPLOAD = 'uploads.github.com'

  TEMP = ENV.fetch('RUNNER_TEMP') { ENV.fetch('RUNNER_WORKSPACE') { ENV['TEMP'] } }

  SEVEN = "C:\\Program Files\\7-Zip\\7z"

  DASH  = ENV['GITHUB_ACTIONS'] ? "\u2500".dup.force_encoding('utf-8') : 151.chr
  LINE  = DASH * 40
  GRN   = "\e[92m"
  RED   = "\e[91m"
  YEL   = "\e[93m"
  RST   = "\e[0m"
  END_GROUP = "##[endgroup]\n"

  # Repo specific constants
  TAG = 'msys2-gcc-pkgs' # GitHub release tag
  MSYS2_ROOT = 'C:/msys64'
  PACMAN     = 'C:/msys64/usr/bin/pacman.exe'
  BASH       = 'C:/msys64/usr/bin/bash.exe'

  def gh_api_graphql(http, query)
    body = {}
    body["query"] = query

    req = Net::HTTP::Post.new '/gh_api_graphql'
    req['Authorization'] = "Bearer #{TOKEN}"
    req['Accept'] = 'application/json'
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate body
    resp = http.request req

    if resp.code == '200'
      body = resp.body
      JSON.parse body, symbolize_names: true
    else
      STDOUT.syswrite "resp.code #{resp.code}\n"
    end
  end

  def gh_api_http
    Net::HTTP.start(GH_API, 443, :use_ssl => true) do |http|
      yield http
    end
  end

  def gh_upload_http
    Net::HTTP.start(GH_UPLOAD, 443, :use_ssl => true) do |http|
      yield http
    end
  end

  def set_v3_common_headers(req, connection: nil)
    req['User-Agent'] = GH_NAME
    req['Authorization'] = "Bearer #{TOKEN}"
    req['Accept'] = 'application/vnd.github+json'  # old 'application/vnd.github.v3+json'
    req['X-GitHub-Api-Version'] = '2022-11-28'
    req['Connection'] = 'close' if connection == 'close'
  end

  def gh_api_v3_get(http, user_repo, suffix, connection: nil)
    req = Net::HTTP::Get.new "/repos/#{user_repo}/#{suffix}"
    set_v3_common_headers req, connection: connection
    resp = http.request req
    resp.code == '200' ? JSON.parse(resp.body) : resp
  end

  def gh_api_v3_patch(http, user_repo, suffix, hsh, connection: nil)
    req = Net::HTTP::Patch.new "/repos/#{user_repo}/#{suffix}"
    set_v3_common_headers req, connection: connection
    req['Content-Type'] = 'application/json; charset=utf-8'
    req.body = JSON.generate hsh

    resp = http.request req
    resp.code == '200' ? JSON.parse(resp.body) : resp
  end

  def gh_api_v3_delete(http, user_repo, suffix, connection: nil)
    req = Net::HTTP::Delete.new "/repos/#{user_repo}/#{suffix}"
    set_v3_common_headers req, connection: connection
    resp = http.request req
    resp.code == '204' ? nil : resp
  end

  def gh_api_v3_upload(http, user_repo, suffix, file, connection: nil)
    unless File.exist?(file) && File.readable?(file)
      STDOUT.syswrite "#{RED}File #{file} doesn't exist or isn't readable#{RST}\n"
      exit 1
    end

    req = Net::HTTP::Post.new "/repos/#{user_repo}/#{suffix}"
    set_v3_common_headers req, connection: connection
    req['Content-Type'] = 'application/x-7z-compressed'
    req['Content-Length'] = File.size file
    io = File.open file, mode: 'rb'
    req.body_stream = io
    resp = http.request req
    io.close unless io.closed?
    resp.code == '201' ? JSON.parse(resp.body) : resp
  end

  def response_ok(response_obj, msg, actions_group: false)
    if response_obj.is_a? Net::HTTPResponse
      out_str = (actions_group ? END_GROUP : '').dup
      out_str << "#{RED}HTTP Error - #{msg} - #{response_obj.code} #{response_obj.message}#{RST}\n"
      if (body = response_obj['body'])
        out_str << "#{JSON.parse(body)}\n"
      end
      STDOUT.syswrite "#{out_str}\n"
      false
    else
      true
    end
  end

  def download(uri_s, file)
    retry_max = 3
    retries = 0
    uri = URI uri_s
    redirect = nil
    begin
      Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        req = Net::HTTP::Get.new uri.request_uri
        http.request req do |resp|
          req['Connection'] = 'close'
          case resp
          when Net::HTTPSuccess then
            File.open file, 'wb' do |io|
              resp.read_body do |chunk|
                io.write chunk
              end
            end
          when Net::HTTPRedirection then
            redirect = resp['location']
            warn "redirected to #{URI(redirect).host}"
          else
            puts "Unknown issue connecting to:\n#{uri}\nCode: #{resp.code}  Class: #{resp.class}"
            resp.value
          end
        end
      end
    rescue Errno::ECONNRESET => e
      if retries > retry_max
        raise e
      else
        puts "Retry"
        retries += 1
        sleep 2
        retry
      end
    end
    download(redirect, file) if redirect
  rescue => e
    STDOUT.syswrite "\nCannot connect to:\n#{uri.host}\n#{uri.request_uri}\n#{File.basename file}\n\n"
    raise e
  end

  def upload_7z_update(pkg_name, time)
    resp_obj   = nil
    body       = nil
    release_id = nil
    old_asset_exists = nil
    new_asset_exists = nil
    current_asset_id = nil
    updated_asset_id = nil

    STDOUT.syswrite "##[group]#{YEL}Upload #{pkg_name}.7z file & update release notes#{RST}\n"

    # get release info
    gh_api_http do |http|
      resp_obj = gh_api_v3_get http, USER_REPO, "releases/tags/#{TAG}",
        connection: 'close'

      break unless response_ok resp_obj, 'GET - release info response', actions_group: true

      release_id   = resp_obj['id']
      assets       = resp_obj['assets']

      old_asset_exists = assets.any? { |asset| asset['name'] == "#{pkg_name}_old.7z" }
      new_asset_exists = assets.any? { |asset| asset['name'] == "#{pkg_name}_new.7z" }

      asset_obj = assets.find { |asset| asset['name'] == "#{pkg_name}.7z" }
      current_asset_id = asset_obj['id'] if asset_obj
    end

    exit 1 if resp_obj.is_a? Net::HTTPResponse

    if old_asset_exists
      STDOUT.syswrite "#{END_GROUP}#{RED}old asset #{pkg_name}_old.7z exists#{RST}\n"
      exit 1
    end

    if new_asset_exists
      STDOUT.syswrite "#{END_GROUP}#{RED}new asset #{pkg_name}_new.7z exists#{RST}\n"
      exit 1
    end

    # Upload new 7z package
    gh_upload_http do |http|
      time_start = Process.clock_gettime Process::CLOCK_MONOTONIC

      resp_obj = gh_api_v3_upload http, USER_REPO,
        "releases/#{release_id}/assets?label=&name=#{pkg_name}_new.7z", "#{pkg_name}.7z",
        connection: 'close'

      break unless response_ok resp_obj, 'POST - upload new 7z package', actions_group: true

      updated_asset_id = resp_obj['id']

      ttl_time = format '%5.2f', (Process.clock_gettime(Process::CLOCK_MONOTONIC) - time_start).round(2)
      STDOUT.syswrite "Upload time: #{ttl_time} secs\n"
    end

    exit 1 if resp_obj.is_a? Net::HTTPResponse

    unless updated_asset_id
      STDOUT.syswrite "#{END_GROUP}#{RED}updated_asset_id not found#{RST}\n"
      exit 1
    end

    sleep 5.0

    # Flip names and update release notes (body)
    gh_api_http do |http|
      time_start = Process.clock_gettime Process::CLOCK_MONOTONIC

      if current_asset_id
        resp_obj = gh_api_v3_patch http, USER_REPO, "releases/assets/#{current_asset_id}", {'name' => "#{pkg_name}_old.7z"}
        break unless response_ok resp_obj, 'PATCH - rename current asset to old', actions_group: true
      end

      resp_obj = gh_api_v3_patch http, USER_REPO, "releases/assets/#{updated_asset_id}", {'name' => "#{pkg_name}.7z"}
      break unless response_ok resp_obj, 'PATCH - rename updated asset to current', actions_group: true

      ttl_time = format '%5.2f', (Process.clock_gettime(Process::CLOCK_MONOTONIC) - time_start).round(2)
      STDOUT.syswrite "Rename time: #{ttl_time} secs\n"

      if current_asset_id
        resp_obj = gh_api_v3_delete http, USER_REPO, "releases/assets/#{current_asset_id}"
        break unless response_ok resp_obj, 'DELETE - remove old asset', actions_group: true
      end

      resp_obj = gh_api_v3_get http, USER_REPO, "releases/#{release_id}"
      break unless response_ok resp_obj, 'GET - release notes response', actions_group: true
      body = resp_obj['body']

      # update package info in release notes
      h = {'body' => update_release_notes(body, pkg_name, time)}
      resp_obj = gh_api_v3_patch http, USER_REPO, "releases/#{release_id}", h,
        connection: 'close'
      break unless response_ok resp_obj, 'PATCH - update release notes with date/build number', actions_group: true
    end

    exit 1 if resp_obj.is_a? Net::HTTPResponse

    Net::HTTP.start('github.com', 443, :use_ssl => true) do |http|
      req = Net::HTTP::Head.new "/#{USER_REPO}/releases/download/#{TAG}/#{pkg_name}.7z"
      resp = http.request req
      if resp.code == '302'
        STDOUT.syswrite "##[endgroup]\n\n#{GRN}HTTP HEAD request #{pkg_name}.7z test - #{resp.code} #{resp.message}#{RST}\n"
      else
        STDOUT.syswrite "##[endgroup]\n\n#{RED}HTTP HEAD request #{pkg_name}.7z test - #{resp.code} #{resp.message}#{RST}\n"
      end
    end
  end

  def update_release_notes(old_body, name, time)
    old_body.sub(/(^\| +\*\*#{name}\*\* +\|).+/) {
      "#{$1} #{time} | #{BUILD_NUMBER.rjust 6} |"
    }
  end

  def gpg_conf_key_server(old_uri, new_uri)
    fn = "#{MSYS2_ROOT}/etc/pacman.d/gnupg/gpg.conf"
    str = File.binread fn
    if str.include? old_uri
      str.sub! old_uri, new_uri
      File.binwrite fn, str
      STDOUT.syswrite "\ngpg.conf - changed '#{old_uri}' to '#{new_uri}'"
    end
  end

  def refresh_keys
    STDOUT.syswrite "\n##[group]#{YEL}#{LINE} Refresh keys#{RST}\n"
    gpg_conf_key_server 'keyserver.ubuntu.com', 'keys.openpgp.org'

    str = ''
    cmd = "#{BASH} -c \"pacman-key --refresh-keys\""

    IO.popen(cmd, err: [:child, :out]) { |io| str = io.read }

    system 'taskkill /f /fi "MODULES eq msys-2.0.dll"'

    STDOUT.syswrite "#{str}\n#{END_GROUP}"

    str.match?(/new signatures:|signatures cleaned:/) ? true : nil
  end

  def pacman_syuu(ignore = nil)

    usr_bin = "#{MSYS2_ROOT}/usr/bin"

    exit 1 unless system "#{usr_bin}/sed -i 's/^CheckSpace/#CheckSpace/g' C:/msys64/etc/pacman.conf"

    ignore = ignore ? "--ignore #{ignore}" : nil

    cmd = "#{PACMAN} -Syuu --disable-download-timeout --noconfirm #{ignore}"

    exec_check 'Updating all installed packages', cmd, false
    system 'taskkill /f /fi "MODULES eq msys-2.0.dll"'
    STDOUT.syswrite END_GROUP

    exec_check 'Updating all installed packages (2nd pass)', cmd, false
    system 'taskkill /f /fi "MODULES eq msys-2.0.dll"'
    STDOUT.syswrite END_GROUP

    refresh_keys
  end

  # logs message and runs cmd, checking for error
  def exec_check(msg, cmd, write_group_end = true)
    STDOUT.syswrite "\n##[group]#{YEL}#{LINE} #{msg}#{RST}\n"
    exit 1 unless system cmd
    STDOUT.syswrite END_GROUP if write_group_end
  end

  def log_array_2_column(ary, wid, hdr)
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
