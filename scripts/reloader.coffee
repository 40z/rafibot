Exec = require('child_process').exec

module.exports = (robot) ->
  robot.respond /reload all scripts/i, (msg) ->
    try
      process.exit()
      Exec './update_and_restart', []
    catch error
      console.log "Hubot reloader:", error
      msg.send "Could not reload all scripts: #{error}"