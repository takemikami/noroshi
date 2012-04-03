require 'optparse'
require 'noroshi/sv'
require 'yaml'

module Noroshi
  class CLI

    def self.get_remote(conf)
      DRb.start_service
      remote = DRbObject.new(nil, Noroshi::SV.get_drubyuri(conf))
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

      case subcmd
      when 'start'
        x = Noroshi::SV.start(conf)
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
          remote = CLI.get_remote(conf)
          p remote.set_values(vals)
        end
      when 'list'
        remote = CLI.get_remote(conf)
        p remote.list
      else
        puts "usage: noroshi [start|stop|add|dataset] [options]"
      end

    end
  end
end
