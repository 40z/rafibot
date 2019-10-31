humanize_duration = require('humanize-duration')
pluralize_lib = require('pluralize')
redis = require('redis')
Articles = require('articles')

char_replace = (str, prev, next) ->
  str.split(prev).join(next);
  
tokenize = (item) ->
  char_replace(item.trim(), ' ', '_').toLowerCase()
  
pluralize = (count, item) ->
  pluralize_lib(item, count, true)

module.exports = (robot) ->
  robot.router.post '/hubot/aptracker/:room', (req, res) ->
    room   = req.params.room
    data   = if req.body.payload? then JSON.parse req.body.payload else req.body
    user = data.user
    tracked_item = data.trackeditem
    action = data.action.replace /^\s+|\s+$/g, ""

    stats = item_stats(robot, user, tracked_item)
    if stats.is_drinking
      if action == "SINGLE" or action == "TOGGLE"
        stop_tracking(robot, room, stats, tracked_item, user)
        res.send '{ "status": "stopped" }'
      else if action == "DOUBLE"
        stop_tracking(robot, room, stats, tracked_item, user)
        res.send '{ "status": "stopped" }'
        sleep 5000
        item_start(robot, user, tracked_item)
        robot.messageRoom room, "#{user} started tracking a #{tracked_item}."
      else if action == "AVERAGE" or action == "REAL SINGLE"
        res.status(403).send '{ "status": "error" }'
    else
      if action == "SINGLE" or action == "TOGGLE"
        item_start(robot, user, tracked_item)
        robot.messageRoom room, "#{user} started tracking a #{tracked_item}."
        res.send '{ "status": "started" }'
      else if action == "DOUBLE"
        item_start(robot, user, tracked_item)
        robot.messageRoom room, "#{user} started tracking a #{tracked_item}."
        res.send '{ "status": "started" }'
        sleep 5000
        stop_tracking(robot, room, stats, tracked_item, user)
      else if action == "REAL SINGLE"
        item_start(robot, user, tracked_item)
        item_stop(robot, user, tracked_item, 5000)
        robot.messageRoom room, "#{user} has tracked #{pluralize stats.count + 1, stats.item}"
        res.send '{ "status": "single" }'
      else if action == "AVERAGE"
        item_start(robot, user, tracked_item)
        item_stop(robot, user, tracked_item, stats.average)
        robot.messageRoom room, "#{user} has tracked #{pluralize stats.count + 1, tracked_item}"
        res.send '{ "status": "started" }'

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
