God.watch do |w|
  w.name = "rafibot"
  w.start = "bin/hubot --adapter slack"
  w.keepalive
end