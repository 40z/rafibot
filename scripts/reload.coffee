exec = require('child_process').exec

module.exports = (robot) ->
  robot.respond /update/i, (msg) ->
    try
      msg.send 'fuck you nerds'
      exec 'cd /home/jimmy/rafibot && git pull origin master', (err, stdout, stderr) ->
        exec("kill $(ps aux | grep 'rafibot' | awk '{print $2}')")
    catch error
      msg.robot.logger.error "rafi reload error #{error}"
      msg.send "Could not update: #{error}"