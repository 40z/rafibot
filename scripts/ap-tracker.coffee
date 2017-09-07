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
      msg.send "You have drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}. Averaging #{humanize(stats.average)}."

  robot.hear /track ap leaderboard/i, (msg) ->
    list = users(robot)
    stats = (ap_stats(robot, user) for user in list)
    stats.sort (a, b) ->
      b.count - a.count

    for stat in stats
      continue if stat.count == 0
      msg.send("#{stat.user} has drank #{stat.count} AP(s)!")

  robot.hear /track ap stats (\S+)$/i, (msg) ->
    user = msg.match[1].replace("@", "")
    stats = ap_stats(robot, user)
    if stats.is_drinking
      msg.send "#{user} has been drinking an AP for #{humanize(stats.current_duration)}."
    else
      msg.send "#{user} has drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}. Averaging #{humanize(stats.average)}."

humanize = (milli) ->
  humanize_duration(milli, { round: true, largest: 2 })

ap_stats = (robot, user) ->
  start_date = robot.brain.get("#{user}_start")
  add_user(robot, user)

  count = robot.brain.get("#{user}_count") || 0
  total_duration = robot.brain.get("#{user}_total") || 0
  average = total_duration / if count == 0 then 1 else count
  current = new Date() - start_date

  user: user
  is_drinking: !!start_date
  start_date: start_date
  count: count
  total_duration: total_duration
  current_duration: current
  average: average

users = (robot) ->
  robot.brain.get('users') || []

add_user = (robot, user) ->
  list = users(robot)
  list.push(user) if user not in list
  robot.brain.set('users', list)

start_ap = (robot, user) ->
  key = "#{user}_start"
  robot.brain.set(key, new Date())

stop_ap = (robot, user) ->
  stats = ap_stats(robot, user)
  robot.brain.set("#{user}_start", null)
  robot.brain.set("#{user}_count", stats.count + 1)
  robot.brain.set("#{user}_total", stats.total_duration + stats.current_duration)
  stats.current_duration
