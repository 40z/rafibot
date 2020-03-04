module.exports = (robot) ->
	robot.hear /^rate (.+) (\d+)\s*(\/|out of)\s*(\d+)(\s+#.*)?/i, (msg) -> rate_item robot, msg.message.user.name, msg.match[1], msg.match[2], msg.match[4], msg.match[5], respond_in_second_person(msg)

	robot.hear /^ranked item (.+) remove tags\s+#(.*)$/i, (msg) -> tag_remove robot, msg.match[1], msg.match[2], respond_in_second_person(msg)

	robot.hear /^ranked item (.+) add tags\s+#(.*)$/i, (msg) -> tag_add robot, msg.match[1], msg.match[2], respond_in_second_person(msg)

	robot.hear /^rank item (.+)$/i, (msg) -> list_item_rank robot, msg.message.user.name, msg.match[1], respond_in_second_person(msg)

	robot.hear /^rank (.+)$/i, (msg) -> list_ranks robot, msg.match[1], respond_in_second_person(msg)

# --------------------------------
# Core Methods
# --------------------------------

redis = require('redis')
char_replace = (str, prev, next) -> str.split(prev).join(next);
sanitize = (item) -> item.replace(/[:,@_#]/g, '').toLowerCase().split(' ').filter((word) -> word.length > 0).join(' ')
tags_from_blob = (tag_blob) -> (t for t in (tag_blob || '').split('#').map(sanitize) when t.length > 0)

get_item_rating = (robot, item) ->
	robot.brain.get("#{item}_ranking") || { item: item, tags: [], overall_rating: 0, user_ratings: [] }

put_item_rating = (robot, item, tags, user_ratings) ->
	overall_rating = if user_ratings.length > 0 then user_ratings.map((user_rating) -> user_rating.rating).reduce((x, y) -> x + y) / user_ratings.length else 0
	robot.brain.set "#{item}_ranking", { item: item, tags: tags, overall_rating: overall_rating, user_ratings: user_ratings }

add_item_rating = (robot, item, user, rating, tags) ->
	item_rating = get_item_rating robot, item
	user_ratings = item_rating.user_ratings.filter (user_rating) -> user_rating.user isnt user
	user_ratings.push { user: user, rating: rating }
	new_tags = item_rating.tags.filter (t) -> t not in tags
	new_tags = new_tags.concat tags
	put_item_rating robot, item, new_tags, user_ratings

get_tag = (robot, tag) ->
	robot.brain.get("#{tag}_tag") || []

put_tag = (robot, tag, items) ->
	robot.brain.set "#{tag}_tag", items

add_tag = (robot, tag, item) ->
	current_items = get_tag robot, tag
	current_items.push(item) if item not in current_items
	put_tag robot, tag, current_items

	item_rating = get_item_rating robot, item
	item_rating.tags.push(tag) if tag not in item_rating.tags
	put_item_rating robot, item_rating.item, item_rating.tags, item_rating.user_ratings

add_tags = (robot, tags, item) ->
	tags.forEach (t) -> add_tag(robot, t, item)

remove_tag = (robot, tag, item) ->
	current_items = get_tag robot, tag
	current_items = current_items.filter (i) -> i isnt item
	put_tag robot, tag, current_items

	item_rating = get_item_rating robot, item
	item_rating.tags = item_rating.tags.filter (t) -> t isnt tag
	put_item_rating robot, item_rating.item, item_rating.tags, item_rating.user_ratings

remove_tags = (robot, tags, item) ->
	tags.forEach (t) -> remove_tag(robot, t, item)

rate_item = (robot, user, item, rating, max_rating, tag_blob, callback) ->
	sanitized_user = sanitize user
	sanitized_item = sanitize item
	tags = tags_from_blob tag_blob
	rating = rating/max_rating

	if rating < 1.5
		add_item_rating robot, sanitized_item, sanitized_user, rating, tags
		add_tags robot, tags, sanitized_item
		list_item_rank robot, user, item, callback
	else
		callback { status: 200, code: MessageCodes.itemRatingTooHigh }

list_item_rank = (robot, user, item, callback) ->
	sanitized_user = sanitize user 
	sanitized_item = sanitize item
	item_rating = get_item_rating robot, sanitized_item
	item_rating.user_rating = (i for i in item_rating.user_ratings when i.user is sanitized_user)[0]
	callback { status: 200, code: MessageCodes.itemRating, ranking: item_rating }

list_ranks = (robot, tag, callback) ->
	sanitized_tag = sanitize tag
	items = get_tag robot, sanitized_tag
	item_ratings = items.map((item) -> get_item_rating(robot, item)).sort (a, b) -> b.overall_rating - a.overall_rating
	callback { status: 200, code: MessageCodes.tagRanking, rankings: item_ratings }

tag_add = (robot, item, tag_blob, callback) ->
	sanitized_item = sanitize item
	tags = tags_from_blob tag_blob
	add_tags robot, tags, sanitized_item
	callback { status: 200, code: MessageCodes.itemTags, ranking: get_item_rating(robot, sanitized_item) }

tag_remove = (robot, item, tag_blob, callback) ->
	sanitized_item = sanitize item
	tags = tags_from_blob tag_blob
	remove_tags robot, tags, sanitized_item
	callback { status: 200, code: MessageCodes.itemTags, ranking: get_item_rating(robot, sanitized_item) }

# --------------------------------
# Translators
# --------------------------------

humanize = (rating) -> "#{(rating * 10).toFixed(1)} out of 10"

respond_in_second_person = (slack) ->
	(response) -> slack.send second_person response

MessageCodes =
	itemRating: 1
	tagRanking: 2
	itemTags: 3
	itemRatingTooHigh: 4

second_person = (response) ->
	return switch response.code
		when 1 then "#{if !!response.ranking.user_rating then "You rated #{response.ranking.item} #{humanize response.ranking.user_rating.rating}\n" else ""}Overall #{response.ranking.item} is rated #{humanize response.ranking.overall_rating}#{if response.ranking.tags.length > 0 then "\n#{response.ranking.item} is tagged as: #{response.ranking.tags.map((t) -> "##{t}").join(", ")}" else ""}"
		when 2 then "#{response.rankings.map((ranking, index) -> "##{index + 1}. #{ranking.item} is rated #{humanize ranking.overall_rating}").join("\n")}"
		when 3 then "#{response.ranking.item} #{if response.ranking.tags.length > 0 then "is tagged as #{response.ranking.tags.map((t) -> "##{t}").join(", ")}" else "has no tags"}"
		when 4 then "That rating is too damn high!"
		else "I don't know what to say about that."