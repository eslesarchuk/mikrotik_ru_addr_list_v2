#!/usr/bin/env ruby

require 'sinatra'
require 'faraday'
require 'json'
require 'socket'

CACHE_DURATION = 24 * 60 * 60 # seconds
SOURCES = {
  'russia' => 'https://www.iwik.org/ipcountry/RU.cidr',
  'belarus' => 'https://www.iwik.org/ipcountry/BY.cidr',
}
# MIKROTIK_LIST = 'russia'
# FILENAME = 'russia.auto.rsc'

$cached_cidrs = nil
$last_fetched_at = nil

set :host_authorization, { permitted_hosts: [] }
set :bind, '0.0.0.0'
set :port, 4777

def server_ipaddrs
  Socket.ip_address_list.reject( &:ipv4_loopback? ).reject( &:ipv6? ).map { |a| a.ip_address }
end

get '/' do
  output = ""
  output << server_ipaddrs.map { |a| "<a href='http://#{a}:#{settings.port}'>#{a}</a><br/>"}.join("\n")
  output << "--------<br/>\n"
  output << SOURCES.map { |c,s| "<a href=\"/#{c}.auto.rsc\">#{c}.auto.rsc</a><br/>" }.join("\n")
  output << "\n<pre>\n"
  output << SOURCES.map { |c,s| "/tool/fetch url=\"#{request.url}#{c}.auto.rsc\" output=file dst-path=flash/#{c}.auto.rsc\n/import file-name=flash/#{c}.auto.rsc" }.join("\n")
  output << "\n/system scheduler\n"
  output << SOURCES.map { |c,s| "add policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=startup name=load_#{c} on-event=\"/import file-name=flash/#{c}.auto.rsc\"" }.join("\n")
  output << "\n"
  output << SOURCES.map { |c,s| "add policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-time=06:00:00 interval=1d name=update_#{c} on-event=\"/tool/fetch url=\\\"#{request.url}#{c}.auto.rsc\\\" output=file dst-path=flash/#{c}.auto.rsc; /import file-name=flash/#{c}.auto.rsc\"" }.join("\n")
  output << "\n</pre>"
  return output
end

SOURCES.each do |country,source|
  get "/#{country}.auto.rsc" do
    now = Time.now
    # update if needed
    if $cached_cidrs.nil? || $last_fetched_at.nil? || (now - $last_fetched_at) > CACHE_DURATION
      begin
        response = Faraday.get(source)
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
    commands = $cached_cidrs.map { |cidr| "/ip f a a a=#{cidr} l=#{country} dy=y com=#{timestamp}" }
    commands.prepend "/ip f address-list rem [/ip f address-list f list=#{country}]"
    return commands.join("\n")
  end
end
