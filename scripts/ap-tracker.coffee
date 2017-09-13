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
      leader_stats = current_leader_stats(robot)
      current_stats = ap_stats(robot, msg.message.user.name)
      msg.send "That AP took you #{humanize(current_stats.current_duration)}."
      if current_stats.count > 5 && current_stats.current_duration > current_stats.average * 2
        stop_ap(robot, msg.message.user.name, current_stats.average)
        msg.send "https://img.wonkette.com/wp-content/uploads/2016/08/phoenix-wright-objection.jpg"
      else
        stop_ap(robot, msg.message.user.name)

      new_leader_stats = current_leader_stats(robot)
      if !!leader_stats && leader_stats.user != new_leader_stats.user
        msg.send "#{new_leader_stats.user} is the new leader with #{new_leader_stats.count} AP(s)! :crown:"
        msg.send "The king is dead, long live the king!"

  robot.hear /track ap stats$/i, (msg) ->
    stats = ap_stats(robot, msg.message.user.name)
    if stats.is_drinking
      msg.send "You have been drinking your AP for #{humanize(stats.current_duration)}."
    else
      msg.send "You have drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}. Averaging #{humanize(stats.average)}."

  robot.hear /track ap leaderboard/i, (msg) ->
    list = users(robot)
    stats_count = (ap_stats(robot, user) for user in list)
    stats_total = stats_count.slice 0
    stats_count.sort (a, b) ->
      b.count - a.count

    stats_total.sort (a, b) ->
      b.total_duration - a.total_duration

    if stats_count.length > 0 && stats_count[0].user == stats_total[0].user
      msg.send("#{stats_count[0].user} is in the lead with #{stats_count[0].count} AP(s) for a total time of #{humanize(stats_count[0].total_duration)}.")
    else if stats_count.length > 0
      msg.send("#{stats_count[0].user} has drank the most AP(s) at #{stats_count[0].count}, but #{stats_total[0].user} has drank the longest with a time of #{humanize(stats_total[0].total_duration)}.")

    for stat in stats_count
      continue if stat.count == 0
      msg.send("#{stat.user} has drank #{stat.count} AP(s)!")
    msg.send("And none for Gretchen Weiner!")

  robot.hear /track ap stats (\S+)$/i, (msg) ->
    user = msg.match[1].replace("@", "")
    stats = ap_stats(robot, user)
    robot.logger.info(user, stats)
    if stats.is_drinking
      msg.send "#{user} has been drinking an AP for #{humanize(stats.current_duration)}."
    else
      msg.send "#{user} has drank #{stats.count} AP(s) for a total time of #{humanize(stats.total_duration)}. Averaging #{humanize(stats.average)}."

humanize = (milli) ->
  humanize_duration(milli, { round: true, largest: 2 })

ap_stats = (robot, user) ->
  start_date = Date.parse(robot.brain.get("#{user}_start"))
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

current_leader_stats = (robot) ->
  list = users(robot)
  stats = (ap_stats(robot, user) for user in list)
  stats.sort (a, b) ->
    b.count - a.count
  if stats.length > 0 then stats[0] else null

add_user = (robot, user) ->
  list = users(robot)
  list.push(user) if user not in list
  robot.brain.set('users', list)

start_ap = (robot, user) ->
  key = "#{user}_start"
  robot.brain.set(key, new Date().toString())

stop_ap = (robot, user, duration = null) ->
  stats = ap_stats(robot, user)
  robot.brain.set("#{user}_start", null)
  robot.brain.set("#{user}_count", stats.count + 1)
  robot.brain.set("#{user}_total", stats.total_duration + (duration || stats.current_duration))
