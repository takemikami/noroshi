require 'optparse'
require 'noroshi/sv'
require 'yaml'

module Noroshi
  class CLI

    def self.get_remote(conf)
      DRb.start_service
      remote = DRbObject.new(nil, Noroshi::SV.get_drubyuri(conf))
    end

    def self.aws_init()
      require 'aws-sdk'
      AWS.config(YAML.load(File.read("/etc/aws.yml")))
    end

    def self.aws_get_myhost_values(conf, myinstanceid)
      instance = AWS::EC2.new.instances[myinstanceid]
      info = {}
      keys = conf['data-keys'].split(/ /)
      keys.each  { |key| info[key] = instance.tags[key] }
      info['id'] = instance.id
      info
    end

    def self.execute(stdout, arguments=[])

      # NOTE: the option -p/--path= is given as an example, and should be replaced in your application.

      subcmd = ""
      subcmd = arguments.shift unless arguments.empty? || arguments[0] =~ /^-/
      param = arguments.shift unless arguments.empty? || arguments[0] =~ /^-/

      options = {
        :config     => '/etc/noroshi/noroshi.yml'
      }
      mandatory_options = %w(  )

      parser = OptionParser.new do |opts|
        opts.banner = <<-BANNER.gsub(/^          /,'')
          This application is wonderful because...

          Usage: #{File.basename($0)} [subcommand] [parameter] [options]

          Sub commands:
            start:      start Noroshi Server
            add_node:   connect to another Noroshi Server
            set_values: set values
            list:       list values

          Options are:
        BANNER
        opts.separator ""
        opts.on("-c", "--config PATH", String,
                "configuration file path.",
                "Default: /etc/noroshi/noroshi.yml") { |arg| options[:config] = arg }
        opts.on("-h", "--help",
                "Show this help message.") { stdout.puts opts; exit }
        opts.parse!(arguments)

        if mandatory_options && mandatory_options.find { |option| options[option.to_sym].nil? }
          stdout.puts opts; exit
        end
      end

      # execute commands
      conf = YAML.load(File.read(options[:config]))

      awsenable = false
      myinstanceid = ""
      if conf['awsmode'] == true
        myinstanceid = `curl --silent http://169.254.169.254/latest/meta-data/instance-id`
        awsenable = true unless myinstanceid == ""
      end

      case subcmd
      when 'start'
        info = nil
        if awsenable 
          require 'aws-sdk'
          initial_nodes = []
          AWS.config(YAML.load(File.read("/etc/aws.yml")))
          instances = AWS::EC2.new.instances
          instances.each_with_index do |instance, idx|
            next unless instance.status.to_s == "running"
            initial_nodes.push(instance.private_ip_address)
            break if initial_nodes.push.length > 20
          end
          conf['initial_nodes'] = initial_nodes.join(" ")
          CLI.aws_init
          info = CLI.aws_get_myhost_values(conf,myinstanceid)
        end
        Noroshi::SV.start(conf, info)
      when 'add_node'
        if param != nil         
          remote = CLI.get_remote(conf)
          remote.add_node(param) 
        end
      when 'set_values'
        vals = {}
        if param != nil
          param.split(/,/).each do |keyval|
            kv_ary = keyval.split(/=/)
            if kv_ary.size == 2
              vals[kv_ary[0]] = kv_ary[1]
            end
          end
          if awsenable
            require 'aws-sdk'
            AWS.config(YAML.load(File.read("/etc/aws.yml")))
            instance = AWS::EC2.new.instances[myinstanceid]
            vals.each_pair {|key, val| instance.tags[key] = val unless key == 'id'}
          end
          remote = CLI.get_remote(conf)
          p remote.set_values(vals)
        end
      when 'sync_values'
        if awsenable
          CLI.aws_init
          info = CLI.aws_get_myhost_values(conf,myinstanceid)
          remote = CLI.get_remote(conf)
          p remote.set_values(info)
        end
      when 'refresh'
        remote = CLI.get_remote(conf)
        p remote.refresh
      when 'list'
        remote = CLI.get_remote(conf)
        p remote.list
      else
        puts "usage: noroshi [start|list|add_node|set_values|sync_values] [options]"
      end

    end
  end
end
