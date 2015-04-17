require_relative "./helper"

WebMock.disable_net_connect!

DNS_RES = [Class.new do
  def target
    "boot2.hogwarts.opinsys.net"
  end
end.new]

DNS_EMPTY_RES = []

describe PuavoRestClient do

  it "by default resolves to to bootserver" do

    Resolv::DNS.stub_any_instance(:getresources, DNS_RES) do

      stub_request(:get, "https://boot2.hogwarts.opinsys.net/foo").
          with(:headers => {'Host'=>'hogwarts.opinsys.net', 'User-Agent'=>'puavo-rest-client'}).
        to_return(:status => 200, :body => "bootserver response")


      client = PuavoRestClient.new({
        :puavo_domain => "hogwarts.opinsys.net"
      })

      res = client.get("/foo")
      assert_equal "bootserver response", res.to_s

    end

  end

  it "ignores dns responses that do not match with puavo domain" do

    PuavoRestClient.stub :read_apiserver_file, "http://api.example.net" do
      Resolv::DNS.stub_any_instance(:getresources, DNS_RES) do

        stub_request(:get, "http://api.example.net/foo").
          with(:headers => {'Host'=>'foo.example.net', 'User-Agent'=>'puavo-rest-client'}).
          to_return(:status => 200, :body => "cloud response")

        client = PuavoRestClient.new({
          :puavo_domain => "foo.example.net"
        })

        res = client.get("/foo")
        assert_equal "cloud response", res.to_s

      end
    end
  end

  it "can force server address" do

    stub_request(:get, "http://forced.example.com/foo").
      with(:headers => {'Host'=>'hogwarts.opinsys.net', 'User-Agent'=>'puavo-rest-client'}).
      to_return(:status => 200, :body => "forced server", :headers => {})

    client = PuavoRestClient.new({
      :puavo_domain => "hogwarts.opinsys.net",
      :server => "http://forced.example.com"
    })

    res = client.get("/foo")
    assert_equal "forced server", res.to_s


  end


  it "can set custom headers" do
    PuavoRestClient.stub :read_apiserver_file, "http://api.example.net" do
      Resolv::DNS.stub_any_instance(:getresources, DNS_RES) do

        stub_request(:get, "http://api.example.net/foo").
          with(:headers => {'Host'=>'custom.host.header.example.com', 'User-Agent'=>'puavo-rest-client'}).
          to_return(:status => 200, :body => "")

        client = PuavoRestClient.new({
          :puavo_domain => "foo.example.net",
          :headers => { "host" => "custom.host.header.example.com" }
        })

        res = client.get("/foo")
        assert_equal 200, res.status

      end
    end

  end

  it "can force dns only usage" do
    Resolv::DNS.stub_any_instance(:getresources, DNS_EMPTY_RES) do

       err = assert_raises PuavoRestClient::ResolvFail do
          PuavoRestClient.new({
            :puavo_domain => "hogwarts.opinsys.net",
            :dns => :only
          })
       end

       assert_equal "Empty DNS response", err.message

    end
  end

  it "can force skip dns" do
    Resolv::DNS.stub_any_instance(:getresources, DNS_RES) do
      PuavoRestClient.stub :read_apiserver_file, "http://api.example.net" do

        stub_request(:get, "http://api.example.net/foo").
          with(:headers => {'Host'=>'hogwarts.opinsys.net', 'User-Agent'=>'puavo-rest-client'}).
          to_return(:status => 200, :body => "", :headers => {})


        client = PuavoRestClient.new({
          :puavo_domain => "hogwarts.opinsys.net",
          :dns => :no
        })

        res = client.get("/foo")
        assert_equal 200, res.status

      end
    end
  end

  it "can retry on fallbacks" do
    Resolv::DNS.stub_any_instance(:getresources, DNS_RES) do
      PuavoRestClient.stub :read_apiserver_file, "http://api.example.net" do

        stub_request(:get, "https://boot2.hogwarts.opinsys.net/foo").to_raise(Errno::ENETUNREACH)

        stub_request(:get, "http://api.example.net/foo").
          with(:headers => {'Connection'=>'close', 'Host'=>'hogwarts.opinsys.net', 'User-Agent'=>'puavo-rest-client'}).
          to_return(:status => 200, :body => "", :headers => {})

        client = PuavoRestClient.new({
          :puavo_domain => "hogwarts.opinsys.net",
          :retry_fallback => true
        })

        res = client.get("/foo")
        assert_equal 200, res.status
        assert_equal "http://api.example.net/foo", res.uri.to_s

      end
    end
  end

  it "errors when all servers fail" do
    Resolv::DNS.stub_any_instance(:getresources, DNS_RES) do
      PuavoRestClient.stub :read_apiserver_file, "http://api.example.net" do

        stub_request(:get, "https://boot2.hogwarts.opinsys.net/foo").to_raise(Errno::ENETUNREACH)
        stub_request(:get, "http://api.example.net/foo").to_raise(Errno::ENETUNREACH)

        err = assert_raises PuavoRestClient::Errno::ENETUNREACH do
          client = PuavoRestClient.new({
            :puavo_domain => "hogwarts.opinsys.net",
            :retry_fallback => true
          })

          client.get("/foo")
        end
      end
    end
  end

end
