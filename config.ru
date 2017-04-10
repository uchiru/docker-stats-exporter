def unbytify(s)
  if s.index("KiB")
    s.to_i*(1024)
  elsif s.index("MiB")
    s.to_i*(1024**2)
  elsif s.index("GiB")
    s.to_i*(1024**3)
  elsif s.index("TiB")
    s.to_i*(1024**4)
  else
    s.to_i
  end
end

run Proc.new { |env| 
  containers = `docker stats --no-stream --format "{{.Container}} -- {{.CPUPerc}} -- {{.MemUsage}}"`.strip.split("\n").map { |line|
    a = line.split(" -- ")
    id = a[0]
    cpu = a[1].sub("%", "").to_f
    used = unbytify(a[2].split("/")[0].strip)
    total = unbytify(a[2].split("/")[1].strip)
    [id, {cpu: cpu, used: used, total: total, labels: {}}]
  }.to_h
  `docker ps --format "{{.ID}} -- {{.Labels}}"`.strip.split("\n").each { |line|
    a = line.split(" -- ")
    id = a[0]
    labels = a[1].to_s.split(",")
    if containers.key?(id)
      labels.each do |l|
        k, v = l.split("=")
        containers[id][:labels][k] = v.to_s
      end
    end
  }

  html = []

  html << "# HELP docker_cpu docker container cpu usage"
  html << "# TYPE docker_cpu counter"
  containers.each do |id, c|
    labels = c[:labels].map { |k, v| ",label_#{k}=\"#{v}\"" }.join
    html << %(docker_cpu{container="#{id}"#{labels}} #{c[:cpu]})
  end

  html << "# HELP docker_used_mem docker container mem usage"
  html << "# TYPE docker_used_mem counter"
  containers.each do |id, c|
    labels = c[:labels].map { |k, v| ",label_#{k}=\"#{v}\"" }.join
    html << %(docker_used_mem{container="#{id}"#{labels}} #{c[:used]})
  end

  html << "# HELP docker_total_mem docker container mem available"
  html << "# TYPE docker_total_mem counter"
  containers.each do |id, c|
    labels = c[:labels].map { |k, v| ",label_#{k}=\"#{v}\"" }.join
    html << %(docker_total_mem{container="#{id}"#{labels}} #{c[:used]})
  end

  ['200', {"Content-Type" => "text/plain"}, [html.join("\n")]]
}
