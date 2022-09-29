#\ -o 0.0.0.0 -p 3120
require 'sinatra'
require 'docker'
require 'file-tail'
require 'parallel'
require 'pp'

LABELS = (ENV["LABELS"] || "").split(",")
puts "LABELS=#{LABELS.join(',')}"
$semaphore = Mutex.new
$cache = {}
$oom_cache = {}
Thread.abort_on_exception = true
Docker.options[:read_timeout] = 1e10

class Helpers
  def self.containers_with_stats
    Parallel.map(Docker::Container.all, in_threads: 15) do |c|
      [c, c.stats]; rescue StandardError; [c, nil]
    end.reject do |_c, s|
      s.nil?
    end
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
      containers = Helpers.containers_with_stats.each_with_object({}) do |(c, s), acc|
        id = c.id
        acc[id] = {
          up: 1,
          used: s["memory_stats"]["usage"],
          max_used: s["memory_stats"]["max_usage"],
          total: s["memory_stats"]["limit"],
          pids: s["pids_stats"]["current"],
          cpu: 0,
          labels: c.info["Labels"]
        }
        next(acc) unless s.dig("cpu_stats", "cpu_usage", "total_usage") && s.dig("cpu_stats", "system_cpu_usage")

        cpu_delta = s.dig("cpu_stats", "cpu_usage", "total_usage") - s.dig("precpu_stats", "cpu_usage", "total_usage")
        system_delta = s.dig("cpu_stats", "system_cpu_usage") - s.dig("precpu_stats", "system_cpu_usage")
        if system_delta > 0.0 && cpu_delta > 0.0
          acc[id][:cpu] = cpu_delta.to_f / system_delta * s.dig("cpu_stats", "online_cpus")
        end

        acc
      end

      $semaphore.synchronize do
        $cache.each do |_id, c|
          c[:up] = c[:pids] = c[:cpu] = c[:used] = c[:max_used] = c[:total] = 0
          c[:labels] = []
        end
        # 3 minutes expiration
        containers.each do |id, c|
          $cache[id] = c.merge(expired: Time.now + 3 * 60)
        end
      end

      # expire caches
      $semaphore.synchronize do
        $cache = $cache.reject { |_id, c| c[:expired] < Time.now }.to_h
        $oom_cache = $oom_cache.reject { |_id, c| c[:expired] < Time.now }.to_h
      end
    rescue StandardError => e
      puts e
      puts e.backtrace
    end
    sleep 5
  end
end

Thread.new do
  Docker::Event.stream(filters: { event: { oom: true } }.to_json) do |event|
    id = event.actor.id
    key = {}

    # 1. check cache
    $semaphore.synchronize do
      key = $cache[id][:labels].merge(c: 1) if $cache.key?(id)
      puts "#{id} oom, ctr info from cache"
    end

    # 2. try to get info from docker engine
    if key.empty?
      begin
        c = Docker::Container.get(id)
        key = (c.info.dig("Config", "Labels") || {}).select { |k, _v| LABELS.include?(k) }.to_h.merge(c: 1)
      rescue StandardError => e
        puts "Error: #{e.inspect}"
      end
    end

    next if key.empty?

    # 3. Increment oom counter
    $semaphore.synchronize do
      puts "oom: increment"
      $oom_cache[key] ||= { value: 0 }
      # 14d expiration for ooms counters
      $oom_cache[key][:expired] = Time.now + 14 * 24 * 60 * 60
      $oom_cache[key][:value] += 1
      puts "#{key.inspect}: ooms = #{$oom_cache[key][:value]}"
    end
  end
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
    [:cpu, "docker_cpu", "docker container cpu usage"]
  ].each do |key, metric, desc|
    html << "# HELP #{metric} #{desc}"
    html << "# TYPE #{metric} counter"
    $semaphore.synchronize do
      $cache.each do |id, c|
        labels = c[:labels].select { |k, _v| LABELS.include?(k) }.map { |k, v| "label_#{k}=\"#{v}\"" }
        labels.unshift(%(container="#{id[0..7]}"))
        html << %(#{metric}{#{labels.join(',')}} #{key == :cpu ? c[key].to_f : c[key].to_i})
      end
    end
  end
  html << "# HELP docker_oom amount of ooms"
  html << "# TYPE docker_oom counter"
  $semaphore.synchronize do
    $oom_cache.each do |key, c|
      labels = key.select { |k, _v| LABELS.include?(k) }.map { |k, v| "label_#{k}=\"#{v}\"" }
      html << %(docker_oom{#{labels.join(',')}} #{c[:value]})
    end
  end
  content_type "text/plain"
  html.join("\n") + "\n"
end

run Sinatra::Application
