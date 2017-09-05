humanize_duration = require('humanize-duration')

module.exports = (robot) ->
  robot.hear /track ap start/i, (msg) ->
    stats = ap_stats(robot, msg.message.user)
    if stats.is_drinking
      msg.send "You are already drinking an AP."
    else
      start_ap(robot, msg.message.user)
      msg.send "Bottoms up!"

  robot.hear /track ap stop/i, (msg) ->
    stats = ap_stats(robot, msg.message.user)
    if !stats.is_drinking
      msg.send "You haven't started drinking an AP."
    else
      msg.send "That AP took you #{humanize(stop_ap(robot, msg.message.user))}."

  robot.hear /track ap stats/i, (msg) ->
    stats = ap_stats(robot, msg.message.user)
    if stats.is_drinking
      msg.send "You have been drinking your AP for #{humanize(stats.current_duration)}."
    else
      msg.send "You have drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}."

humanize = (milli) ->
  humanize_duration(milli, { round: true, largest: 2 })

ap_stats = (robot, user) ->
  start_date = robot.brain.get("#{user.name}_start")
  return {
    is_drinking: start_date != null,
    start_date: start_date,
    count: robot.brain.get("#{user.name}_count") || 0,
    total_duration: robot.brain.get("#{user.name}_total") || 0,
    current_duration: new Date() - start_date
  }

start_ap = (robot, user) ->
  key = "#{user.name}_start"
  robot.brain.set(key, new Date())

stop_ap = (robot, user) ->
  stats = ap_stats(robot, user)
  robot.brain.set("#{user.name}_start", null)
  robot.brain.set("#{user.name}_count", stats.count + 1)
  robot.brain.set("#{user.name}_total", stats.total_duration + stats.current_duration)
  stats.current_duration
