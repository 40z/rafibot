module.exports = (robot) ->
	robot.hear /track (.+) start$/i, (msg) ->
		user = get_tracking_user robot, msg.message.user.name
		track_item_start robot, user, msg.match[1], respond_in_second_person(msg)

	robot.hear /track (.+) stop$/i, (msg) ->
		user = get_tracking_user robot, msg.message.user.name
		track_item_stop robot, user, msg.match[1], respond_in_second_person(msg)

	robot.hear /track single (.+)$/i, (msg) ->
		user = get_tracking_user robot, msg.message.user.name
		track_item_single robot, user, msg.match[1], respond_in_second_person(msg)

	robot.hear /track average (.+)$/i, (msg) ->
		user = get_tracking_user robot, msg.message.user.name
		track_item_average robot, user, msg.match[1], respond_in_second_person(msg)

	robot.hear /track (.*) cancel$/i, (msg) ->
		user = get_tracking_user robot, msg.message.user.name
		track_item_cancel robot, user, msg.match[1], respond_in_second_person(msg)

	robot.hear /track merge (.+) : (.+)$/i, (msg) ->
		user = get_tracking_user robot, msg.message.user.name
		merge_item robot, user, msg.match[1], msg.match[2], respond_in_second_person(msg)

	robot.hear /track (.+) leaderboard$/i, (msg) -> list_leaderboard robot, msg.match[1], respond_in_second_person(msg)

	robot.hear /add user alias (.+)$/i, (msg) -> add_user_alias robot, msg.message.user.name, msg.match[1], respond_in_second_person(msg)

	robot.hear /track (?:(current) )?(?:(.+) )?stats(?: (\S+))?$/i, (msg) ->
		user = if msg.match[3] then msg.match[3] else get_tracking_user(robot, msg.message.user.name)
		callback = if msg.match[3] then respond_in_third_person(msg) else respond_in_second_person(msg)
		only_current = !!msg.match[1]
		if !msg.match[2]
			list_stats robot, user, only_current, callback
		else
			list_item_stats robot, user, msg.match[2], only_current, callback

	robot.router.post '/hubot/aptracker/v2/users/:user/track', (req, res) ->
		if req.body.action == null or req.body.item == null or req.body.room == null
			res.status(400).send { status: 400, code: 17 }
			return

		switch req.body.action
			when "toggle" then track_item_toggle robot, req.params.user, req.body.item, respond_with_json_and_in_room(res, robot, req.body.room)
			when "single" then track_item_single robot, req.params.user, req.body.item, respond_with_json_and_in_room(res, robot, req.body.room)
			when "average" then track_item_average robot, req.params.user, req.body.item, respond_with_json_and_in_room(res, robot, req.body.room)

	robot.router.get '/hubot/aptracker/v2/users/:user/stats', (req, res) ->
		list_stats robot, req.params.user, false, respond_with_json(res)


# --------------------------------
# Core Methods
# --------------------------------

redis = require('redis')
Url = require('url')
char_replace = (str, prev, next) -> str.split(prev).join(next);
tokenize = (item) -> char_replace(item.trim(), ' ', '_').toLowerCase()
restore = (item) -> char_replace(item, '_', ' ')

check_leader = (robot, item, wrapped_func) ->
	old_leader_stats = get_item_leader_stats(robot, item)
	wrapped_func()
	new_leader_stats = get_item_leader_stats(robot, item)
	old_leader_stats != null and new_leader_stats != null and old_leader_stats.user != new_leader_stats.user

get_tracking_user = (robot, user) ->
	normalized_user = user.toLowerCase().replace("@", "")
	robot.brain.get("#{normalized_user}_alias") || user

add_user = (robot, user) ->
	list = get_users(robot)
	list.push(user) if user not in list
	robot.brain.set('users', list)

get_users = (robot) ->
	robot.brain.get('users') || []

put_item_stats = (robot, user, item, start_date, count, total_duration) ->
	tokenized_item = tokenize item
	normalized_user = user.toLowerCase().replace("@", "")
	robot.brain.set "#{normalized_user}_#{tokenized_item}_start", start_date?.toString()
	robot.brain.set "#{normalized_user}_#{tokenized_item}_count", count
	robot.brain.set "#{normalized_user}_#{tokenized_item}_total", total_duration

get_item_stats = (robot, user, item) ->
	tokenized_item = tokenize item
	normalized_user = user.toLowerCase().replace("@", "")
	add_user(robot, normalized_user)

	raw_start_date = robot.brain.get("#{normalized_user}_#{tokenized_item}_start")
	start_date = if !!raw_start_date then new Date(raw_start_date) else null
	count = robot.brain.get("#{normalized_user}_#{tokenized_item}_count") || 0
	total_duration = robot.brain.get("#{normalized_user}_#{tokenized_item}_total") || 0
	average = total_duration / if count == 0 then 1 else count
	current = if !!start_date then (new Date() - start_date) else 0

	user: user
	item: item
	tokenized_item: tokenized_item
	is_drinking: !!start_date
	start_date: start_date
	count: count
	total_duration: total_duration
	current_duration: current
	average: average

get_item_leader_stats = (robot, item) ->
	all_users = get_users(robot)
	stats = (get_item_stats(robot, user, item) for user in all_users).sort (a, b) -> b.count - a.count
	if stats.length > 0 then stats[0] else null

list_item_stats = (robot, user, item, showOnlyCurrent, callback) ->
	stats = get_item_stats(robot, user, item)
	code = if showOnlyCurrent then MessageCodes.currentItemStats else MessageCodes.itemStats
	callback { status: 200, code: code, stats: stats }

list_stats = (robot, user, showOnlyCurrent, callback) ->
	info = Url.parse process.env.REDIS_URL or 'redis://localhost:6379', true
	client = redis.createClient(info.port, info.hostname)
	code = if showOnlyCurrent then MessageCodes.currentStats else MessageCodes.stats
	normalized_user = user.toLowerCase().replace("@", "")
	client.get "hubot:storage", (error, reply) ->
		json = JSON.parse(reply.toString())
		keys = Object.keys(json["_private"]).map (key) -> key.match "^#{normalized_user}_(.+)_start$"
		tracking_stats = (get_item_stats(robot, user, key[1]) for key in keys when !!key)
		tracking_stats = tracking_stats.filter (stat) -> stat.is_drinking
		tracking_items = tracking_stats.map (stat) -> restore(stat.item)

		keys = Object.keys(json["_private"]).map (key) -> key.match "^#{normalized_user}_(.+)_count$"
		tracked_stats = (get_item_stats(robot, user, key[1]) for key in keys when !!key)
		tracked_stats = tracked_stats.filter (stat) -> stat.count != 0
		tracked_stats.sort (a, b) -> b.count - a.count
		tracked_items = tracked_stats.map (stat) -> "#{stat.count} #{restore(stat.item)}"

		callback { status: 200, code: code, user: user, current_items: tracking_items, all_items: tracked_items}

list_leaderboard = (robot, item, callback) ->
	all_users = get_users(robot)
	stats_by_count = (get_item_stats(robot, user, item) for user in all_users).sort (a, b) -> b.count - a.count
	stats_by_total = (stats_by_count.slice 0).sort (a, b) -> b.total_duration - a.total_duration
	leaderboard = (stats_by_count.slice 0).filter (a) -> a.count != 0
	count_leader = if stats_by_count.length > 0 && stats_by_count[0].count > 0 then stats_by_count[0] else null
	total_leader = if stats_by_total.length > 0 && stats_by_total[0].total_duration > 0 then stats_by_total[0] else null
	callback { status: 200, code: MessageCodes.leaderBoard, count_leader: count_leader, total_leader: total_leader, leaderboard: leaderboard }

track_item_start = (robot, user, item, callback) ->
	stats = get_item_stats(robot, user, item)
	if stats.is_drinking then callback { status: 400, code: MessageCodes.alreadyDrinking, stats: stats }; return
	put_item_stats(robot, user, item, new Date(), stats.count, stats.total_duration)
	callback { status: 200, code: MessageCodes.startTracking, stats: get_item_stats(robot, user, item) }

track_item_stop = (robot, user, item, callback) ->
	stats = get_item_stats(robot, user, item)
	if !stats.is_drinking then callback { status: 400, code: MessageCodes.notDrinking, stats: stats }; return
	objection = stats.count > 5 and stats.current_duration > stats.average * 2 and stats.current_duration > 10800000
	new_duration = stats.total_duration + if objection then stats.average else stats.current_duration
	is_new_leader = check_leader robot, item, -> put_item_stats(robot, user, item, null, stats.count + 1, new_duration)
	code = if objection then MessageCodes.stopObjection else MessageCodes.stopTracking
	callback { status: 200, code: code, is_new_leader: is_new_leader, stats: get_item_stats(robot, user, item), duration: stats.current_duration }

track_item_single = (robot, user, item, callback) ->
	stats = get_item_stats(robot, user, item)
	is_new_leader = check_leader robot, item, -> put_item_stats(robot, user, item, stats.start_date, stats.count + 1, stats.total_duration + 5000)
	callback { status: 200, code: MessageCodes.numberOfTracks, is_new_leader: is_new_leader, stats: get_item_stats(robot, user, item) }

track_item_toggle = (robot, user, item, callback) ->
	stats = get_item_stats(robot, user, item)
	if stats.is_drinking
		track_item_stop robot, user, item, callback
	else
		track_item_start robot, user, item, callback

track_item_average = (robot, user, item, callback) ->
	stats = get_item_stats(robot, user, item)
	is_new_leader = check_leader robot, item, -> put_item_stats(robot, user, item, stats.start_date, stats.count + 1, stats.total_duration + stats.average)
	callback { status: 200, code: MessageCodes.numberOfTracks, is_new_leader: is_new_leader, stats: get_item_stats(robot, user, item) }

track_item_cancel = (robot, user, item, callback) ->
	stats = get_item_stats(robot, user, item)
	if !stats.is_drinking then { status: 400, code: MessageCodes.notDrinking, stats: stats }; return
	put_item_stats(robot, user, item, null, stats.count, stats.total_duration)
	callback { status: 200, code: MessageCodes.cancelTracking, stats: get_item_stats(robot, user, item) }

merge_item = (robot, user, from_item, to_item, callback) ->
	from_stats = get_item_stats(robot, user, from_item)
	to_stats = get_item_stats(robot, user, to_item)
	if from_stats.tokenized_item == to_stats.tokenized_item then callback { status: 403, code: MessageCodes.mergeSameItem, stats: from_stats }; return
	start_date = to_stats.start_date || from_stats.start_date
	put_item_stats(robot, user, to_item, start_date, from_stats.count + to_stats.count, from_stats.total_duration + to_stats.total_duration)
	put_item_stats(robot, user, from_item, null, null, null)
	callback { status: 200, code: MessageCodes.merged, from_item: from_item, stats: get_item_stats(robot, user, to_item) }

add_user_alias = (robot, user, alias, callback) ->
	normalized_user = user.toLowerCase().replace("@", "")
	robot.brain.set("#{normalized_user}_alias", alias)
	callback { status: 200, code: MessageCodes.aliasAdded }

# --------------------------------
# Translators
# --------------------------------

humanize_duration = require('humanize-duration')
Articles = require('articles')
pluralize_lib = require('pluralize')
humanize = (milli) -> humanize_duration(milli, { round: true, largest: 2 })
articlize = (item) -> Articles.articlize(item)
pluralize = (count, item) -> pluralize_lib(item, count, true)

respond_in_second_person = (slack) ->
	(response) -> slack.send second_person response

respond_in_third_person = (slack) ->
	(response) -> slack.send third_person response

respond_with_json = (web) ->
	(response) -> web.status(response.status).send response

respond_with_json_and_in_room = (web, robot, room) ->
	(response) ->
		web.status(response.status).send response
		robot.messageRoom room, third_person(response)

MessageCodes =
	alreadyDrinking: 1
	startTracking: 2
	notDrinking: 3
	stopTracking: 4
	numberOfTracks: 5
	cancelTracking: 6
	itemStats: 7
	currentItemStats: 8
	stopObjection: 9
	mergeSameItem: 11
	merged: 12
	stats: 14
	currentStats: 15
	leaderBoard: 16
	aliasAdded: 17

second_person = (response) ->
	new_king = (a) -> "#{if a.is_new_leader then "\n#{a.stats.user} is the new leader with #{pluralize a.stats.count, a.stats.item}! :crown:\nThe king is dead, long live the king!" else ""}"
	item_stats = (a) -> "#{if a.stats.is_drinking then "You have been tracking #{articlize a.stats.item} for #{humanize a.stats.current_duration}.\n" else ""}You have tracked #{pluralize a.stats.count, a.stats.item} for a total time of #{humanize a.stats.total_duration}. Averaging #{humanize a.stats.average}."
	return switch response.code
		when MessageCodes.alreadyDrinking then "You are already drinking #{articlize response.stats.item}"
		when MessageCodes.startTracking then "Bottoms up!"
		when MessageCodes.notDrinking then "You have not started drinking #{articlize response.stats.item}"
		when MessageCodes.stopTracking then "That #{response.stats.item} took you #{humanize response.duration}#{new_king response}"
		when MessageCodes.numberOfTracks then "You have tracked #{pluralize response.stats.count, response.stats.item}#{new_king response}"
		when MessageCodes.cancelTracking then "Try harder or I'll find someone who can!"
		when MessageCodes.itemStats then item_stats(response)
		when MessageCodes.currentItemStats then "#{if response.stats.is_drinking then "You have been tracking #{articlize response.stats.item} for #{humanize response.stats.current_duration}." else "You are not tracking #{articlize response.stats.item}"}"
		when MessageCodes.stopObjection then "That #{response.stats.item} took you #{humanize response.duration}\nhttps://www.bgreco.net/objection/objection.gif"
		when MessageCodes.mergeSameItem then "Can't merge an item into itself"
		when MessageCodes.merged then "Merged #{response.from_item} into #{response.stats.item}\n#{item_stats response}"
		when MessageCodes.stats then "#{if response.current_items.length > 0 then "You are currently tracking:\n#{response.current_items.join("\n")}\n" else ""}#{if response.all_items.length > 0 then "You have tracked:\n#{response.all_items.join("\n")}" else "You have tracked nothing"}"
		when MessageCodes.currentStats then "#{if response.current_items.length > 0 then "You are currently tracking:\n#{response.current_items.join("\n")}" else "You are currently tracking nothing"}"
		when MessageCodes.leaderBoard
			message = ""
			if response.count_leader != null and response.total_leader != null and response.count_leader.user != response.total_leader.user
				message += "#{response.count_leader.user} drank the most #{pluralize_lib response.count_leader.item, response.count_leader.count} at #{response.count_leader.count}, but #{response.total_leader.user} drank the longest with a time of #{humanize response.total_leader.total_duration}\n"
			else if response.count_leader != null
				message += "#{response.count_leader.user} drank the most #{pluralize_lib response.count_leader.item, response.count_leader.count} at #{response.count_leader.count}\n"
			message += "#{("#{stat.user} drank #{pluralize stat.count, stat.item}!" for stat in response.leaderboard).join("\n")}"
		when MessageCodes.aliasAdded then "Alias added"
		else "I don't know what to say about that."

third_person = (response) ->
	current_item_stats = (a) -> "#{a.stats.user} has been tracking #{articlize a.stats.item} for #{humanize a.stats.current_duration}."
	current_items = (a) -> "#{a.user} is currently tracking:\n#{a.current_items.join("\n")}"
	new_king = (a) -> "#{if a.is_new_leader then "\n#{a.stats.user} is the new leader with #{pluralize a.stats.count, a.stats.item}! :crown:\nThe king is dead, long live the king!" else ""}"
	return switch response.code
		when MessageCodes.startTracking then "#{response.stats.user} started tracking #{articlize response.stats.item}"
		when MessageCodes.stopTracking then "That #{response.stats.item} took #{response.stats.user} #{humanize response.duration}#{new_king response}"
		when MessageCodes.numberOfTracks then "#{response.stats.user} has tracked #{pluralize response.stats.count, response.stats.item}#{new_king response}"
		when MessageCodes.itemStats then "#{if response.stats.is_drinking then "#{current_item_stats response}\n" else ""}#{response.stats.user} has tracked #{pluralize response.stats.count, response.stats.item} for a total time of #{humanize response.stats.total_duration}. Averaging #{humanize response.stats.average}."
		when MessageCodes.currentItemStats then "#{if response.stats.is_drinking then current_item_stats(response) else "#{response.stats.user} is not tracking #{articlize response.stats.item}"}"
		when MessageCodes.stats then "#{if response.current_items.length > 0 then "#{current_items response}\n" else ""}#{if response.all_items.length > 0 then "#{response.user} has tracked:\n#{response.all_items.join("\n")}" else "#{response.user} has tracked nothing"}"
		when MessageCodes.currentStats then "#{if response.current_items.length > 0 then current_items(response) else "#{response.user} is currently tracking nothing"}"
		else "I don't know what to say about that."
