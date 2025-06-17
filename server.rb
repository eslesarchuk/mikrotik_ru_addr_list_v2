#!/usr/bin/env ruby

require 'sinatra'
require 'faraday'
require 'json'

SOURCE = 'https://www.iwik.org/ipcountry/RU.cidr'
CACHE_DURATION = 24 * 60 * 60 # seconds
MIKROTIK_LIST = 'russia'
FILENAME = 'russia.auto.rsc'

$cached_cidrs = nil
$last_fetched_at = nil

set :host_authorization, { permitted_hosts: [] }
set :bind, '0.0.0.0'
set :port, 4777

get '/' do
  return """
  <a href=\"/#{FILENAME}\">#{FILENAME}</a>
  <pre>
  /tool/fetch url=\"#{request.url}#{FILENAME}\" output=file dst-path=flash/#{FILENAME}
  /import file-name=flash/#{FILENAME}

  /system scheduler
  add comment=reboot name=load_russia on-event=\"/import file-name=flash/#{FILENAME}\" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup
  add interval=1d start-time=06:00:00 name=update_russia on-event=\"/tool/fetch url=\\\"#{request.url}#{FILENAME}\\\" output=file dst-path=flash/#{FILENAME}; /import file-name=flash/#{FILENAME}\" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon
  </pre>
  """
end

get "/#{FILENAME}" do
  now = Time.now
  # update if needed
  if $cached_cidrs.nil? || $last_fetched_at.nil? || (now - $last_fetched_at) > CACHE_DURATION
    begin
      response = Faraday.get(SOURCE)
      if response.success?
        cidrs = response.body.lines.map(&:strip).reject do |line|
          line.empty? || line.start_with?('#')
        end
        $cached_cidrs = cidrs
        $last_fetched_at = now
      else
        # their end error
        status response.status
        return response.body
      end
    rescue Faraday::Error => e
      # our end error
      status 500
      return 'request error'
    end
  end
  # actual output
  content_type 'text/plain'
  timestamp = Time.now.strftime('%d%b%Y').downcase
  commands = $cached_cidrs.map { |cidr| "/ip f a a a=#{cidr} l=#{MIKROTIK_LIST} dy=y com=#{timestamp}" }
  commands.prepend "/ip f address-list rem [/ip f address-list f list=#{MIKROTIK_LIST}]"
  return commands.join("\n")
end
