#\ -o 0.0.0.0 -p 3120
require 'sinatra'
require 'honeybadger'
require 'docker'
require 'parallel'
require 'pp'

LABELS = (ENV["LABELS"] || "").split(",")
puts "LABELS=#{LABELS.join(",")}"
$cache = {}

Honeybadger.exception_filter do |notice|
  notice[:error_message] =~ /SignalException: SIGTERM/
end

class Helpers 
  def self.containers_with_stats
    Parallel.map(Docker::Container.all, in_threads: 15) { |c|
      begin; [c, c.stats]; rescue; [c, nil]; end
    }.reject { |c, s|
      s.nil?
    }
  end

  def self.honey_context
    out = {}
    out["project_name"] = ENV["PROJECT_NAME"] if ENV["PROJECT_NAME"]
    out["nomad_ip"] = ENV["NOMAD_IP_port"] if ENV["NOMAD_IP_port"]
    out
  end
end

Thread.new do
  loop do
    begin
      puts "Grab docker info: #{Time.now}"
      start = {}
      containers = Helpers.containers_with_stats.map { |c, s|
        id = c.id[0..11]
        start[id] = [s["cpu_stats"]["cpu_usage"]["total_usage"], s["cpu_stats"]["system_cpu_usage"]]
        [id, {
          up: 1,
          used: s["memory_stats"]["usage"],
          max_used: s["memory_stats"]["max_usage"],
          total: s["memory_stats"]["limit"],
          pids: s["pids_stats"]["current"],
          cpu: 0,
          labels: c.info["Labels"].select { |k, v| LABELS.index(k) }.to_h,
        }]
      }.to_h
      sleep 1.0
      Helpers.containers_with_stats.each { |c, s|
        id = c.id[0..11]
        # https://github.com/moby/moby/blob/131e2bf12b2e1b3ee31b628a501f96bbb901f479/api/client/stats.go#L309
        if containers.key?(id) && start[id] && start[id][0] && start[id][1] && s["cpu_stats"]["cpu_usage"]["total_usage"] && s["cpu_stats"]["system_cpu_usage"]
          cpuDelta = s["cpu_stats"]["cpu_usage"]["total_usage"] - start[id][0]
          systemDelta = s["cpu_stats"]["system_cpu_usage"] - start[id][1]
          if systemDelta > 0.0 && cpuDelta > 0.0 
            containers[id][:cpu] = cpuDelta.to_f/systemDelta*s["cpu_stats"]["cpu_usage"]["percpu_usage"].length
          end
        end
      }

      $cache.each { |id, c| c[:up] = c[:pids] = c[:cpu] = c[:used] = c[:max_used] = c[:total] = 0 }
      # 3 minutes expiration
      containers.each { |id, c| $cache[id] = c.merge(expired: Time.now + 3*60) }
      $cache = $cache.reject { |id, c| c[:expired] < Time.now }.to_h
    rescue => e
      puts e
      puts e.backtrace
      Honeybadger.notify(e, context: Helpers.honey_context)
    end
    sleep 5
  end
end

before do
  Honeybadger.context(Helpers.honey_context)
end

get "/" do
  "<a href=/metrics>metrics</a>"
end

get "/test_500" do
  raise '500'
end

get "/metrics" do
  html = []
  [
    [:up, "docker_up", "docker container availability"],
    [:used, "docker_used_mem", "docker container mem usage"],
    [:max_used, "docker_max_used_mem", "docker container max mem usage"],
    [:total, "docker_total_mem", "docker container mem available"],
    [:pids, "docker_pids", "docker container pids amount"],
    [:cpu, "docker_cpu", "docker container cpu usage"],
  ].each do |key, metric, desc|
    html << "# HELP #{metric} #{desc}"
    html << "# TYPE #{metric} counter"
    $cache.each do |id, c|
      labels = c[:labels].select { |k, v| LABELS.index(k) }.map { |k, v| ",label_#{k}=\"#{v}\"" }.join
      html << %(#{metric}{container="#{id}"#{labels}} #{key == :cpu ? c[key].to_f : c[key].to_i})
    end
  end
  content_type "text/plain"
  html.join("\n") + "\n"
end

run Sinatra::Application
