require "rack/readiness/version"
require "json"
require "worker_scoreboard"

module Rack
  class Readiness
    def initialize(app, options = {})
      @app             = app
      @uptime          = Time.now.to_i
      @skip_ps_command = options[:skip_ps_command] || false
      @path            = options[:path] || '/readiness'
      @allow           = options[:allow] || []
      scoreboard_path  = options[:scoreboard_path]
      unless scoreboard_path.nil?
        @scoreboard = WorkerScoreboard.new(scoreboard_path)
      end
    end

    def call(env)
      if env['PATH_INFO'] == @path
        handle_server_status(env)
      else
        @app.call(env)
      end
    end

    private

    def allowed?(address)
      return true if @allow.empty?
      @allow.include?(address)
    end

    def handle_server_status(env)
      unless allowed?(env['REMOTE_ADDR'])
        return [403, {'Content-Type' => 'text/plain'}, [ 'Forbidden' ]]
      end

      upsince = Time.now.to_i - @uptime
      duration = "#{upsince} seconds"
      body = "Uptime: #{@uptime} (#{duration})\n"
      status = {Uptime: @uptime}

      if @scoreboard.nil?
        return [503, {'Content-Type' => 'text/plain'}, [body]]
      end

      stats = @scoreboard.read_all
      parent_pid = Process.ppid
      all_workers = []
      idle = 0
      busy = 0
      if @skip_ps_command
        all_workers = stats.keys
      elsif RUBY_PLATFORM !~ /mswin(?!ce)|mingw|cygwin|bccwin/
        ps = `LC_ALL=C command ps -e -o ppid,pid`
        ps.each_line do |line|
          line.lstrip!
          next if line =~ /^\D/
          ppid, pid = line.chomp.split(/\s+/, 2)
          all_workers << pid.to_i if ppid.to_i == parent_pid
        end
      else
        all_workers = stats.keys
      end
      process_status_str = ''
      process_status_list = []

      all_workers.each do |pid|
        json =stats[pid] || '{}'
        pstatus = begin; JSON.parse(json, symbolize_names: true); rescue; end
        pstatus ||= {}
        if !pstatus[:status].nil? && pstatus[:status] == 'A'
          busy += 1
        else
          idle += 1
        end
        unless pstatus[:time].nil?
          pstatus[:ss] = Time.now.to_i - pstatus[:time].to_i
        end
        pstatus[:pid] ||= pid
        pstatus.delete :time
        pstatus.delete :ppid
        pstatus.delete :uptime
        process_status_str << sprintf("%s\n", [:pid, :status, :remote_addr, :host, :method, :uri, :protocol, :ss].map {|item| pstatus[item] || '' }.join(' '))
        process_status_list << pstatus
      end

      body << <<"EOF"
BusyWorkers: #{busy}
IdleWorkers: #{idle}
--
pid status remote_addr host method uri protocol ss
#{process_status_str}
EOF
      body.chomp!
      status[:BusyWorkers] = busy
      status[:IdleWorkers] = idle
      status[:stats]       = process_status_list

      if idle > 0
        if (env['QUERY_STRING'] || '') =~ /\bjson\b/
          return [200, {'Content-Type' => 'application/json; charset=utf-8'}, [status.to_json]]
        else
          return [200, {'Content-Type' => 'text/plain'}, [body]]
        end
      else
        if (env['QUERY_STRING'] || '') =~ /\bjson\b/
          return [503, {'Content-Type' => 'application/json; charset=utf-8'}, [status.to_json]]
        else
          return [503, {'Content-Type' => 'text/plain'}, [body]]
        end
      end
    end
  end
end
