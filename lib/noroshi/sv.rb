# -*- coding: utf-8 -*-
require 'logger'
require 'rgossip2'
require "drb/drb"
require 'erb'
require 'fileutils'

module Noroshi
  class SV

    @logger = nil
    @gossip = nil
    @keys = nil
    @mydata = nil
    @mtx = nil
    @callback_proc = nil
   
    def datastr_tohash(datastr)
      dataset = {}
      if datastr != nil
        data_array = datastr.split(/\t/)
        @keys.each_with_index do |key, idx|
          dataset[key] = data_array[idx] unless data_array[idx] == nil
        end
      end
      dataset
    end

    def initialize(conf)
      @logger = Logger.new($stderr)
      @keys = []
      @mydata = {}
      initial_nodes = nil
      @mtx = Mutex::new
      address = SV.get_localipaddress
      @keys = conf['data-keys'].split(/ /) if  conf && conf['data-keys']
      initial_nodes = conf['initial_nodes'] if conf && conf['initial_nodes']
      callback_dir = conf['callback-dir'] if conf && conf['callback-dir']

      @callback_proc = Proc.new do |args|
        @logger.info("callback: #{args}")
        if args[0] == :add || args[0] == :delete || (args[0] == :update && args[3] != args[4])
          Dir::glob("#{callback_dir}/*.yml").each do |f|
            @logger.debug("target callback yml: #{f}")
            cb_conf = YAML.load(File.read(f))
            fromdata = datastr_tohash(args[3])
            todata = datastr_tohash(args[4])
            execute_flg = true
            if cb_conf['condition']
              execute_flg = false
              cb_conf['condition'].each_pair do |key, value|
                if fromdata[key] =~ /#{value}/ || todata[key] =~ /#{value}/
                  execute_flg = true
                end
              end
            end
            @mtx.synchronize do
              if execute_flg
                if cb_conf['conf-file']
                  execute_flg = false
                  cb_conf['conf-file'].each do |cf|
                    if SV.apply_template("#{callback_dir}/#{cf['template']}",  cf['file'], list)
                      @logger.info("create config file by callback: #{cf['file']} (#{callback_dir}/#{cf['template']})")
                      execute_flg = true
                    else
                      @logger.info("skip config file update by callback: #{cf['file']} (#{callback_dir}/#{cf['template']})")
                    end
                  end
                end
              end
              if execute_flg
                if cb_conf['execute']
                  cb_conf['execute'].each do |exe|
                    @logger.info("execute callback command: #{exe['cmd']}")
                    begin
                      `execute #{exe['cmd']}`
                    rescue => ex
                      @logger.error("callback command error: #{ex} (#{exe['cmd']})")
                    end
                  end
                end
              end
            end
          end
        end
      end

      @gossip = RGossip2.client(
        :initial_nodes => initial_nodes,
        :address => address,
        :auth_key => conf['auth-key'],
        :callback_handler => @callback_proc,
      )

      @logger.info("Noroshi Server is initialized")
    end

    def add_node(node)
      @gossip.add_node node
    end

    def stop
      @gossip.stop
      @logger.info("Noroshi Servers (gossip server process) is stopped")
    end

    def set_values(values)
      values.each_pair do |key, val|
        @mydata[key] = val
      end
      dataset = []
      @keys.each_with_index do |key, idx|
        dataset.push(@mydata[key])
      end
      old_data = @gossip.data
      new_data = dataset.join("\t")
      if old_data != new_data 
        @gossip.data = new_data
        @callback_proc.call([:update,nil,nil,@gossip.data,old_data])
        @logger.info("local node data updated: #{values}")
      end
    end

    def list
      rtn = []
      @gossip.each do |address, timestamp, data|
        dataset = {
          'address' => address,
          'timestamp' => timestamp,
        }
        if data != nil
          data_array = data.split(/\t/)
          @keys.each_with_index do |key, idx|
            dataset[key] = data_array[idx] unless data_array[idx] == nil
          end
        end
        rtn.push(dataset)
      end
      rtn
    end

    class << self

      def apply_template(template_name, target_name, hostlist)
        update_status = false
        template_str = ""
        open("#{template_name}",'r') do |fp|
          template_str = fp.read
        end
        erb = ERB.new(template_str)
        newconf_str = erb.result(binding)
        oldconf_str = ""
        open("#{target_name}",'r') { |fp| oldconf_str = fp.read } if File.exists?(target_name)
        if oldconf_str.chomp != newconf_str.chomp
          open("#{target_name}.tmp",'w') do |fp|
            fp.puts newconf_str
          end
          FileUtils.cp("#{target_name}.tmp","#{target_name}")
          FileUtils.rm("#{target_name}.tmp")
          update_status = true
        end
        update_status
      end

      def get_localipaddress
        localip = ""
        ifconfig = `ifconfig`
        ifconfig.split(/\n/).each do |line|
         if line =~ /inet ([0-9.]*)/
           localip = $1
           break unless localip == "127.0.0.1"
         end
        end
        localip
      end

      def get_drubyuri(conf)
        druby_uri = "druby://localhost:"
        if conf && conf['druby-port'] && conf['druby-port'] =~ /\d+/
          druby_uri + conf['druby-port']
        else
          druby_uri + "1121"
        end
      end

      def start(conf)
#        Process.daemon
        DRb.start_service(get_drubyuri(conf), SV.new(conf))

        Signal.trap(:EXIT) do
          remote = DRbObject.new(nil, Noroshi::SV.get_drubyuri(conf))
          remote.stop
          puts "Noroshi Server is stopped"
          DRb.stop_service()
        end

        DRb.thread.join
      end
    end

  end
end
