humanize_duration = require('humanize-duration')

module.exports = (robot) ->
  robot.hear /track ap start/i, (msg) ->
    stats = ap_stats(robot, msg.message.user.name)
    if stats.is_drinking
      msg.send "You are already drinking an AP."
    else
      start_ap(robot, msg.message.user.name)
      msg.send "Bottoms up!"

  robot.hear /track ap stop/i, (msg) ->
    stats = ap_stats(robot, msg.message.user.name)
    if !stats.is_drinking
      msg.send "You haven't started drinking an AP."
    else
      msg.send "That AP took you #{humanize(stop_ap(robot, msg.message.user.name))}."

  robot.hear /track ap stats$/i, (msg) ->
    stats = ap_stats(robot, msg.message.user.name)
    if stats.is_drinking
      msg.send "You have been drinking your AP for #{humanize(stats.current_duration)}."
    else
      msg.send "You have drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}."

  robot.hear /track ap stats (\S+)$/i, (msg) ->
    user = msg.match[1].replace("@", "")
    stats = ap_stats(robot, user)
    if stats.is_drinking
      msg.send "#{user} has been drinking an AP for #{humanize(stats.current_duration)}."
    else
      msg.send "#{user} has drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}."

humanize = (milli) ->
  humanize_duration(milli, { round: true, largest: 2 })

ap_stats = (robot, user) ->
  start_date = robot.brain.get("#{user}_start")
  return {
    is_drinking: start_date != null,
    start_date: start_date,
    count: robot.brain.get("#{user}_count") || 0,
    total_duration: robot.brain.get("#{user}_total") || 0,
    current_duration: new Date() - start_date
  }

start_ap = (robot, user) ->
  key = "#{user}_start"
  robot.brain.set(key, new Date())

stop_ap = (robot, user) ->
  stats = ap_stats(robot, user)
  robot.brain.set("#{user}_start", null)
  robot.brain.set("#{user}_count", stats.count + 1)
  robot.brain.set("#{user}_total", stats.total_duration + stats.current_duration)
  stats.current_duration
