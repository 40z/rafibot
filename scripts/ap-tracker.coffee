humanize_duration = require('humanize-duration')
pluralize_lib = require('pluralize')
redis = require('redis')
Articles = require('articles')

char_replace = (str, prev, next) ->
  str.split(prev).join(next);
  
tokenize = (item) ->
  char_replace(item.trim(), ' ', '_').toLowerCase()
  
restore = (item) -> 
  char_replace(item, '_', ' ')

articlize = (item) ->
  Articles.articlize(item)

pluralize = (count, item) ->
  pluralize_lib(item, count, true)

module.exports = (robot) ->
  robot.hear /track (.+) start/i, (msg) ->
    stats = item_stats(robot, msg.message.user.name, msg.match[1])
    if stats.is_drinking
      msg.send "You are already drinking #{articlize stats.item}."
    else
      item_start(robot, msg.message.user.name, msg.match[1])
      msg.send "Bottoms up!"

  robot.hear /track (.+) stop/i, (msg) ->
    stats = item_stats(robot, msg.message.user.name, msg.match[1])
    if !stats.is_drinking
      msg.send "You haven't started drinking #{articlize stats.item}."
    else
      stop_tracking(robot, msg.message.room, stats, msg.match[1], msg.message.user.name)

  robot.hear /^track single (.+)$/i, (msg) -> track_single_item(robot, msg)

  robot.hear /^track average (.+)$/i, (msg) -> track_average_item(robot, msg)

  robot.hear /track merge (.+) : (.+)$/i, (msg) ->
    if tokenize(msg.match[1]) == tokenize(msg.match[2])
      msg.send "Can't merge an item into itself"
      return
      
    user = msg.message.user.name
    from_stats = item_stats(robot, user, msg.match[1])
    to_stats = item_stats(robot, user, msg.match[2])

    current = to_stats.start_date || from_stats.start_date
    put_item_stats(robot, user, to_stats.item, current, from_stats.count + to_stats.count, from_stats.total_duration + to_stats.total_duration)
    put_item_stats(robot, user, from_stats.item, null, null, null)
    msg.send("Merged #{msg.match[1]} into #{msg.match[2]}")

    merged_stats = item_stats(robot, user, msg.match[2])
    if merged_stats.is_drinking
      msg.send "#{user} has been drinking #{articlize merged_stats.item} for #{humanize merged_stats.current_duration}."
    msg.send "#{user} drank #{pluralize merged_stats.count, merged_stats.item} for a total time of #{humanize merged_stats.total_duration}. Averaging #{humanize merged_stats.average}."

  robot.hear /track (.+) leaderboard/i, (msg) ->
    list = users(robot)
    stats_count = (item_stats(robot, user, msg.match[1]) for user in list)
    stats_total = stats_count.slice 0
    stats_count.sort (a, b) ->
      b.count - a.count

    stats_total.sort (a, b) ->
      b.total_duration - a.total_duration

    if stats_count.length > 0 && stats_count[0].user == stats_total[0].user && stats_count[0].count > 0
      msg.send("#{stats_count[0].user} is in the lead with #{pluralize stats_count[0].count, stats_count[0].item} for a total time of #{humanize(stats_count[0].total_duration)}.")
    else if stats_count.length > 0 && stats_count[0].count > 0
      msg.send("#{stats_count[0].user} drank the most #{pluralize_lib stats_count[0].item, stats_count[0].count} at #{stats_count[0].count}, but #{stats_total[0].user} drank the longest with a time of #{humanize(stats_total[0].total_duration)}.")

    for stat in stats_count
      continue if stat.count == 0
      msg.send("#{stat.user} drank #{pluralize stat.count, stat.item}!")
    msg.send("And none for Gretchen Weiner!")

  robot.hear /track (?:(current) )?(?:(.+) )?stats(?: (\S+))?$/i, (msg) ->
    user = if msg.match[3] then msg.match[3].replace("@", "") else msg.message.user.name
    if !msg.match[2]
      track_stats robot, msg, !!msg.match[1], user
    else
      track_item_stats robot, msg, msg.match[2], !!msg.match[1], user

  robot.router.post '/hubot/aptracker/:room', (req, res) ->
    room   = req.params.room
    data   = if req.body.payload? then JSON.parse req.body.payload else req.body
    user = data.user
    tracked_item = data.trackeditem
    action = data.action.replace /^\s+|\s+$/g, ""

    stats = item_stats(robot, user, tracked_item)
    if stats.is_drinking
      stop_tracking(robot, room, stats, tracked_item, user)
      if action == "DOUBLE"
        sleep 5000
        item_start(robot, user, tracked_item)
        robot.messageRoom room, "#{user} started tracking a #{tracked_item}."
    else
      item_start(robot, user, tracked_item)
      robot.messageRoom room, "#{user} started tracking a #{tracked_item}."
      if action == "DOUBLE"
        sleep 5000
        stop_tracking(robot, room, stats, tracked_item, user)

    res.send 'OK'

track_single_item = (robot, msg, user = msg.message.user.name) ->
  item = msg.match[1]
  stats = item_stats(robot, user, item)
  if stats.is_drinking
    msg.send "You are already tracking #{articlize stats.item}."
  else
    item_start(robot, user, item)
    item_stop(robot, user, item, 5000)
    msg.send "You have tracked #{pluralize stats.count + 1, stats.item}"

track_average_item = (robot, msg, user = msg.message.user.name) ->
  item = msg.match[1]
  stats = item_stats(robot, user, item)
  if stats.is_drinking
    msg.send "You are already tracking #{articlize stats.item}."
  else
    item_start(robot, user, item)
    item_stop(robot, user, item, stats.average)
    msg.send "You have tracked #{pluralize stats.count + 1, stats.item}"

track_item_stats = (robot, msg, item, showOnlyCurrent, user = msg.message.user.name) ->
  secondPerson = msg.message.user.name == user
  stats = item_stats(robot, user, msg.match[2])
  if stats.is_drinking
    subject_action = if secondPerson then "You have" else "#{user} has"
    msg.send "#{subject_action} been tracking #{articlize stats.item} for #{humanize stats.current_duration}."
  else if showOnlyCurrent
    subject_action = if secondPerson then "You are" else "#{user} is"
    msg.send "#{subject_action} not tracking #{articlize stats.item}"

  if !showOnlyCurrent
    subject_action = if secondPerson then "You have" else "#{user} has"
    msg.send "#{subject_action} tracked #{pluralize stats.count, stats.item} for a total time of #{humanize stats.total_duration}. Averaging #{humanize stats.average}." 

track_stats = (robot, msg, showOnlyCurrent, user = msg.message.user.name) ->
  secondPerson = msg.message.user.name == user
  client = redis.createClient()
  client.get "hubot:storage", (error, reply) ->
    json = JSON.parse(reply.toString())
    keys = Object.keys(json["_private"]).map (key) -> key.match "^#{user}_(.+)_start$"
    tracking_stats = (item_stats(robot, user, key[1]) for key in keys when !!key)
    tracking_stats = tracking_stats.filter (stat) -> stat.is_drinking
    tracking_items = tracking_stats.map (stat) -> restore(stat.item)
    subject_action = if secondPerson then "You are" else "#{user} is"
    if tracking_items.length > 0 then msg.send "#{subject_action} currently tracking:\n#{tracking_items.join("\n")}"
    else if showOnlyCurrent then msg.send "#{subject_action} currently tracking nothing"

    if !showOnlyCurrent
      keys = Object.keys(json["_private"]).map (key) -> key.match "^#{user}_(.+)_count$"
      tracked_stats = (item_stats(robot, user, key[1]) for key in keys when !!key)
      tracked_stats = tracked_stats.filter (stat) -> stat.count != 0
      tracked_stats.sort (a, b) -> b.count - a.count
      tracked_items = tracked_stats.map (stat) -> "#{stat.count} #{restore(stat.item)}"
      subject_action = if secondPerson then "You have" else "#{user} has"
      if tracked_items.length > 0
        msg.send "#{subject_action} tracked:\n#{tracked_items.join("\n")}"
      else
        msg.send "#{subject_action} tracked nothing"

stop_tracking = (robot, room, stats, tracked_item, user) ->
  leader_stats = current_leader_stats(robot, tracked_item)
  current_stats = item_stats(robot, user, tracked_item)
  robot.messageRoom room, "That #{stats.item} took #{user} #{humanize current_stats.current_duration}."
  if current_stats.count > 5 && current_stats.current_duration > current_stats.average * 2 && current_stats.current_duration > 10800000
    item_stop(robot, user, tracked_item, current_stats.average)
    robot.messageRoom room, "https://www.bgreco.net/objection/objection.gif"
  else
    item_stop(robot, user, tracked_item)

  new_leader_stats = current_leader_stats(robot, tracked_item)
  if !!leader_stats && leader_stats.user != new_leader_stats.user
    robot.messageRoom room, "#{new_leader_stats.user} is the new leader with #{pluralize new_leader_stats.count, new_leader_stats.item}! :crown:"
    robot.messageRoom room, "The king is dead, long live the king!"

humanize = (milli) ->
  humanize_duration(milli, { round: true, largest: 2 })

item_stats = (robot, user, item) ->
  item_to_track = tokenize(item)
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

put_item_stats = (robot, user, item, start_date, count, total_duration) ->
  item_to_track = tokenize(item)
  date = if !!start_date then new Date(start_date).toString() else null
  robot.brain.set("#{user}_#{item_to_track}_start", date)
  robot.brain.set("#{user}_#{item_to_track}_count", count)
  robot.brain.set("#{user}_#{item_to_track}_total", total_duration)

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
  item_to_track = tokenize(item)
  key = "#{user}_#{item_to_track}_start"
  robot.brain.set(key, new Date().toString())

item_stop = (robot, user, item, duration = null) ->
  item_to_track = tokenize(item)
  stats = item_stats(robot, user, item)
  robot.brain.set("#{user}_#{item_to_track}_start", null)
  robot.brain.set("#{user}_#{item_to_track}_count", stats.count + 1)
  robot.brain.set("#{user}_#{item_to_track}_total", stats.total_duration + (duration || stats.current_duration))

sleep = (ms) ->
  start = new Date().getTime()
  continue while new Date().getTime() - start < ms
