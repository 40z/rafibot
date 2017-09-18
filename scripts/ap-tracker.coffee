humanize_duration = require('humanize-duration')

module.exports = (robot) ->
  robot.hear /track (.+) start/i, (msg) ->
    stats = item_stats(robot, msg.message.user.name, msg.match[1])
    if stats.is_drinking
      msg.send "You are already drinking a #{stats.item}."
    else
      item_start(robot, msg.message.user.name, msg.match[1])
      msg.send "Bottoms up!"

  robot.hear /track (.+) stop/i, (msg) ->
    stats = item_stats(robot, msg.message.user.name, msg.match[1])
    if !stats.is_drinking
      msg.send "You haven't started drinking a #{stats.item}."
    else
      leader_stats = current_leader_stats(robot, msg.match[1])
      current_stats = item_stats(robot, msg.message.user.name, msg.match[1])
      msg.send "That #{stats.item} took you #{humanize(current_stats.current_duration)}."
      if current_stats.count > 5 && current_stats.current_duration > current_stats.average * 2
        item_stop(robot, msg.message.user.name, msg.match[1], current_stats.average)
        msg.send "https://img.wonkette.com/wp-content/uploads/2016/08/phoenix-wright-objection.jpg"
      else
        item_stop(robot, msg.message.user.name, msg.match[1])

      new_leader_stats = current_leader_stats(robot, msg.match[1])
      if !!leader_stats && leader_stats.user != new_leader_stats.user
        msg.send "#{new_leader_stats.user} is the new leader with #{new_leader_stats.count} #{new_leader_stats.item}(s)! :crown:"
        msg.send "The king is dead, long live the king!"

  robot.hear /track (.+) stats$/i, (msg) ->
    stats = item_stats(robot, msg.message.user.name, msg.match[1])
    if stats.is_drinking
      msg.send "You have been drinking your #{stats.item} for #{humanize(stats.current_duration)}."
    else
      msg.send "You have drank #{stats.count} #{stats.item}(s) for a total time of #{humanize(stats.total_duration)}. Averaging #{humanize(stats.average)}."

  robot.hear /track (.+) leaderboard/i, (msg) ->
    list = users(robot)
    stats_count = (item_stats(robot, user, msg.match[1]) for user in list)
    stats_total = stats_count.slice 0
    stats_count.sort (a, b) ->
      b.count - a.count

    stats_total.sort (a, b) ->
      b.total_duration - a.total_duration

    if stats_count.length > 0 && stats_count[0].user == stats_total[0].user && stats_count[0].count > 0
      msg.send("#{stats_count[0].user} is in the lead with #{stats_count[0].count} #{stats_count[0].item}(s) for a total time of #{humanize(stats_count[0].total_duration)}.")
    else if stats_count.length > 0 && stats_count[0].count > 0
      msg.send("#{stats_count[0].user} drank the most #{stats_count[0].item}(s) at #{stats_count[0].count}, but #{stats_total[0].user} drank the longest with a time of #{humanize(stats_total[0].total_duration)}.")

    for stat in stats_count
      continue if stat.count == 0
      msg.send("#{stat.user} drank #{stat.count} #{stat.item}(s)!")
    msg.send("And none for Gretchen Weiner!")

  robot.hear /track (.+) stats (\S+)$/i, (msg) ->
    user = msg.match[2].replace("@", "")
    stats = item_stats(robot, user, msg.match[1])
    if stats.is_drinking
      msg.send "#{user} has been drinking a #{stats.item} for #{humanize(stats.current_duration)}."
    else
      msg.send "#{user} drank #{stats.count} #{stats.item}(s) for a total time of #{humanize(stats.total_duration)}. Averaging #{humanize(stats.average)}."

humanize = (milli) ->
  humanize_duration(milli, { round: true, largest: 2 })

sanitize = (item) ->
  item.replace(" ", "_").toLowerCase()

item_stats = (robot, user, item) ->
  item_to_track = sanitize(item)
  start_date = Date.parse(robot.brain.get("#{user}_#{item_to_track}_start"))
  add_user(robot, user)

  count = robot.brain.get("#{user}_#{item_to_track}_count") || 0
  total_duration = robot.brain.get("#{user}_#{item_to_track}_total") || 0
  average = total_duration / if count == 0 then 1 else count
  current = new Date() - start_date

  user: user
  item: item
  is_drinking: !!start_date
  start_date: start_date
  count: count
  total_duration: total_duration
  current_duration: current
  average: average

users = (robot) ->
  robot.brain.get('users') || []

current_leader_stats = (robot, item) ->
  list = users(robot)
  stats = (item_stats(robot, user, item) for user in list)
  stats.sort (a, b) ->
    b.count - a.count
  if stats.length > 0 then stats[0] else null

add_user = (robot, user) ->
  list = users(robot)
  list.push(user) if user not in list
  robot.brain.set('users', list)

item_start = (robot, user, item) ->
  item_to_track = sanitize(item)
  key = "#{user}_#{item_to_track}_start"
  robot.brain.set(key, new Date().toString())

item_stop = (robot, user, item, duration = null) ->
  item_to_track = sanitize(item)
  stats = item_stats(robot, user, item)
  robot.brain.set("#{user}_#{item_to_track}_start", null)
  robot.brain.set("#{user}_#{item_to_track}_count", stats.count + 1)
  robot.brain.set("#{user}_#{item_to_track}_total", stats.total_duration + (duration || stats.current_duration))
