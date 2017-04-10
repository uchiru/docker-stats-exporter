run Proc.new { |env| 
  html = "Hi"
  ['200', {"Content-Type" => "text/html"}, [html]]
}
