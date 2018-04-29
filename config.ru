#\ -o 0.0.0.0 -p 3120
require 'sinatra'
require 'honeybadger'
require 'docker'

LABELS = (ENV["LABELS"] || "").split(",")
puts "LABELS=#{LABELS.join(",")}"

get "/" do
  "<a href=/metrics>metrics</a>"
end

get "/test_500" do
  raise '500'
end

$cache = {}
get "/metrics" do
  start = {}
  containers = Docker::Container.all.map { |c|
    s = c.stats
    id = c.id[0..11]
    start[id] = [s["cpu_stats"]["cpu_usage"]["total_usage"], s["cpu_stats"]["system_cpu_usage"]]
    [id, {
      name: c.info["Names"].first.to_s[1..-1], up: 1,
      used: s["memory_stats"]["usage"], total: s["memory_stats"]["limit"],
      pids: s["pids_stats"]["current"],
      cpu: 0,
      labels: c.info["Labels"]
    }]
  }.to_h
  sleep 1.0
  Docker::Container.all.each { |c|
    s = c.stats
    id = c.id[0..11]
    if containers.key?(id)
      # https://github.com/moby/moby/blob/131e2bf12b2e1b3ee31b628a501f96bbb901f479/api/client/stats.go#L309
      cpuDelta = s["cpu_stats"]["cpu_usage"]["total_usage"] - start[id][0]
      systemDelta = s["cpu_stats"]["system_cpu_usage"] - start[id][1]
      if systemDelta > 0.0 && cpuDelta > 0.0 
        containers[id][:cpu] = cpuDelta.to_f/systemDelta*s["cpu_stats"]["cpu_usage"]["percpu_usage"].length
      end
    end
  }

  $cache.each { |id, c| c[:up] = c[:pids] = c[:cpu] = c[:used] = c[:total] = 0 }
  # 3 minutes expiration
  containers.each { |id, c| $cache[id] = c.merge(expired: Time.now + 3*60) }
  $cache = $cache.reject { |id, c| c[:expired] < Time.now }.to_h

  html = []
  [
    [:up, "docker_up", "docker container availability"],
    [:used, "docker_used_mem", "docker container mem usage"],
    [:total, "docker_total_mem", "docker container mem available"],
    [:pids, "docker_pids", "docker container pids amount"],
    [:cpu, "docker_cpu", "docker container cpu usage"],
  ].each do |key, metric, desc|
    html << "# HELP #{metric} #{desc}"
    html << "# TYPE #{metric} counter"
    $cache.each do |id, c|
      labels = c[:labels].select { |k, v| LABELS.index(k) }.map { |k, v| ",label_#{k}=\"#{v}\"" }.join
      html << %(#{metric}{container="#{id}",name="#{c[:name]}"#{labels}} #{c[key]})
    end
  end
  content_type "text/plain"
  html.join("\n") + "\n"
end

run Sinatra::Application
