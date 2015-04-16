
require "puavo/gems"
require "gssapi"
require "http"
require "optparse"
require "resolv"
require "addressable/uri"


if ENV["PUAVO_REST_CLIENT_VERBOSE"]
    $puavo_rest_client_verbose = true
end

class PuavoRestClient

  def self.verbose(*msg)
    if $puavo_rest_client_verbose
      STDERR.puts(*msg)
    end
  end

  def verbose(*msg)
    self.class.verbose(*msg)
  end


  def self.public_ssl
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    ctx.ca_path = "/etc/ssl/certs"
    return ctx
  end

  def self.custom_ssl(ca_file="/etc/puavo/certs/rootca.pem")
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    ctx.ca_file = ca_file
    return ctx
  end

  class ResolvFail < Exception
  end

  def self.resolve_apiserver_dns(puavo_domain)

      res = Resolv::DNS.open do |dns|
        dns.getresources(
          "_puavo-api._tcp.#{ puavo_domain }",
          Resolv::DNS::Resource::IN::SRV
        )
      end

      if res.nil? || res.empty?
        raise ResolvFail, "Empty response"
      end

      server_host = res.first.target.to_s
      if !server_host.end_with?(puavo_domain)
        raise ResolvFail, "Invalid value. #{ server_host } does not match with requested puavo domain #{ puavo_domain }. Using master puavo-rest as fallback"
      end

      verbose("Resolved to bootserver puavo-rest #{ server_host }")
      return Addressable::URI.parse("https://#{ server_host }:443")
  end

  def read_apiserver_file
    server = File.open("/etc/puavo/apiserver").read.strip
    if /^https?:\/\//.match(server)
      return server
    else
      return "https://#{ server }"
    end
  end

  def initialize(_options={})
    @options = _options.dup
    @servers = []
    @headers = {
      "user-agent" => "puavo-rest-client"
    }
    @header_overrides = (_options[:headers] || {}).dup

    if @options[:puavo_domain].nil?
      verbose("Using puavo domain from /etc/puavo/domain")
      @options[:puavo_domain] = File.open("/etc/puavo/domain").read.strip
    end

    if @options[:server]
      @servers = [
        :uri => Addressable::URI.parse(@options[:server]),
        :ssl_context => self.class.public_ssl
      ]
    else

      if @options[:dns] != :no
        begin
          @servers.push({
            :uri => Addressable::URI.parse(self.class.resolve_apiserver_dns(@options[:puavo_domain])),
            :ssl_context => self.class.custom_ssl
          })
        rescue ResolvFail => err
          # Crash if only dns is allowed
          raise err if @options[:dns] == :only
        end
      end

      if @options[:dns] != :only
        begin
          @servers.push({
            :uri => self.class.read_apiserver_file,
            :ssl_context => self.class.public_ssl
          })
        rescue Errno::ENOENT
          verbose("/etc/puavo/apiserver is missing")
          @servers.push({
            :uri => "https://#{ @options[:puavo_domain] }",
            :ssl_context => self.class.public_ssl
          })
        end
      end

    end

    # Set request header to puavo domain. Using this we can make requests to
    # api.opinsys.fi with basic auth and get the correct organisation
    @headers["host"] = @options[:puavo_domain]


    # Force usage of custom ca_file if set
    if @options[:ca_file]
      @servers.each do |server|
        server[:ssl_context] = self.class.custom_ssl(@options[:ca_file])
      end
    end

    if @options[:port]
      @servers.each do |server|
        server[:uri].port = @options[:port]
      end
    end

    if @options[:scheme]
      @servers.each do |server|
        server[:uri].scheme = @options[:scheme]
      end
    end

    if @options[:auth] == :bootserver
      @headers["authorization"] = "Bootserver"
    end

    if @options[:auth] == :etc
      verbose("Using credendials from /etc/puavo/ldap/")
      @options[:basic_auth] = {
        :user => File.open("/etc/puavo/ldap/dn").read.strip,
        :pass => File.open("/etc/puavo/ldap/password").read.strip
      }
    end
  end

  def servers
    @servers.map{|s| s.to_s}
  end

  [:get, :post].each do |method|
    define_method(method) do |path, *options|

      url = to_full_url(path)

      verbose("#{ method.to_s.upcase } #{ url }")
      res = client.send(method, url, *options)
      verbose("HTTP STATUS #{ res.status }")
      res
    end
  end

  private

  # http.rb client getter. Must be called for each request in order to get new
  # kerberos ticket since one ticket can be used only for  one request
  def client
    headers = @headers.dup
    _client = HTTP::Client.new(:ssl_context => @options[:ssl_context])

    if @options[:auth] == :kerberos
      gsscli = GSSAPI::Simple.new(@options[:server_host], "HTTP")
      token = gsscli.init_context(nil, :delegate => true)
      headers["authorization"] = "Negotiate #{Base64.strict_encode64(token)}"
    end

    # Add custom header overrides given by the user
    headers.merge!(@header_overrides)

    _client = _client.with_headers(headers)
    verbose("REQUEST HEADERS: #{ headers.inspect }")

    if @options[:basic_auth]
      _client = _client.basic_auth(@options[:basic_auth])
    end

    return _client
  end
end
