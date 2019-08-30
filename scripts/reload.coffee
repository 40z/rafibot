exec = require('child_process').exec

module.exports = (robot) ->
  robot.respond /update( .*)?/i, (msg) ->
    try
      msg.send 'smokebomb'
      branch = if msg.match[1] then msg.match[1].trim() else "master"
      exec 'cd /home/jimmy/rafibot && git pull origin #{branch}', (err, stdout, stderr) ->
        exec("kill $(ps aux | grep -v grep | grep 'rafibot' | awk '{print $2}')")
    catch error
      msg.robot.logger.error "rafi reload error #{error}"
      msg.send "Could not update: #{error}"
