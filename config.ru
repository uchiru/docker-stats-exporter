def unbytify(s)
  if s.index("KiB")
    s.to_f*(1024)
  elsif s.index("MiB")
    s.to_f*(1024**2)
  elsif s.index("GiB")
    s.to_f*(1024**3)
  elsif s.index("TiB")
    s.to_f*(1024**4)

  elsif s.index("kB")
    s.to_f*(1000)
  elsif s.index("MB")
    s.to_f*(1000**2)
  elsif s.index("GB")
    s.to_f*(1000**3)
  elsif s.index("TB")
    s.to_f*(1000**4)

  else
    s.to_f
  end
end

run Proc.new { |env| 
  containers = `docker stats --no-stream --format "{{.Container}} -- {{.Name}} -- {{.CPUPerc}} -- {{.MemUsage}} -- {{.BlockIO}} -- {{.NetIO}}"`.strip.split("\n").map { |line|
    a = line.split(" -- ")
    id = a[0]
    name = a[1]
    cpu = a[2].sub("%", "").to_f
    used = unbytify(a[3].split("/")[0].strip)
    total = unbytify(a[3].split("/")[1].strip)
    block_i = unbytify(a[4].split("/")[0].strip)
    block_o = unbytify(a[4].split("/")[1].strip)
    net_i = unbytify(a[5].split("/")[0].strip)
    net_o = unbytify(a[5].split("/")[1].strip)
    [id, {cpu: cpu, name: name, used: used, total: total, block_i: block_i, block_o: block_o, net_i: net_i, net_o: net_o, labels: {}}]
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
  [
    [:cpu, "docker_cpu", "docker container cpu usage"],
    [:used, "docker_used_mem", "docker container mem usage"],
    [:total, "docker_total_mem", "docker container mem available"],
    [:block_i, "docker_block_i", "docker container block input"],
    [:block_o, "docker_block_o", "docker container block output"],
    [:net_i, "docker_net_i", "docker container net input"],
    [:net_o, "docker_net_o", "docker container net output"],
  ].each do |key, metric, desc|
    html << "# HELP #{metric} #{desc}"
    html << "# TYPE #{metric} counter"
    containers.each do |id, c|
      labels = c[:labels].map { |k, v| ",label_#{k}=\"#{v}\"" }.join
      html << %(#{metric}{container="#{id}",name=#{c[:name]}#{labels}} #{c[key]})
    end
  end

  ['200', {"Content-Type" => "text/plain"}, [html.join("\n") + "\n"]]
}
