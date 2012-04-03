require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'noroshi/sv'
require 'fileutils'

describe Noroshi::SV, "execute" do
  before(:each) do
#    @stdout_io = StringIO.new
#    Noroshi::SV.execute(@stdout_io, [])
#    @stdout_io.rewind
#    @stdout = @stdout_io.read
  end

  it "make druby uri" do
    conf = nil
    x = Noroshi::SV.get_drubyuri(conf)
    x.should == "druby://localhost:1121"

    conf = {}
    conf['druby-port'] = "123"
    x = Noroshi::SV.get_drubyuri(conf)
    x.should == "druby://localhost:123"

    conf = {}
    conf['druby-port'] = "xyz"
    x = Noroshi::SV.get_drubyuri(conf)
    x.should == "druby://localhost:1121"
  end

  it "get ipaddress" do
    x = Noroshi::SV.get_localipaddress()
    x.should_not == "127.0.0.1"
    x.should =~ /[0-9.]*/
  end

  it "apply template" do
    erb_file = File.expand_path(File.dirname(__FILE__) + "/../etc/callback.d/websv-nginx.erb")
    target_file = "./applytemplate.tmp"
    hostlist = []
    hostlist.push({'Name'=>'hoge', 'env'=>'production', 'chef_recipes'=>'app-server'})
    x = Noroshi::SV.apply_template(erb_file, target_file, hostlist)
    target_str = ""
    open("#{target_file}",'r') { |fp| target_str = fp.read }
    target_str.should =~ /hoge/
    FileUtils.rm(target_file)
  end
  
#  it "server start" do
#    conf = YAML.load(File.read(File.expand_path(File.dirname(__FILE__) + "/../etc/noroshi.yml")))
#    x = Noroshi::SV.start(conf)
#    #@stdout.should =~ /To update this executable/
#  end

end
