humanize_duration = require('humanize-duration')
redis = require('redis')

module.exports = (robot) ->

    robot.hear /^(.+) lan (on|is) (.+)/i, (msg) ->
        lan_token = tokenize(msg.match[1])
        date = Date.parse(msg.match[3])
        if isNaN(date)
            msg.send "I can't parse that date. Try '01/01/2019'."
        else
            robot.brain.set(lan_token, date)
            msg.send "GET HYPE!"

    robot.hear /last lan/i, (msg) ->
        client = redis.createClient()
        client.get "hubot:storage", (error, reply) ->
            json = JSON.parse(reply.toString())["_private"]
            keys = (match[0] for match in Object.keys(json).map((key) -> key.match "^lan_(.+)") when !!match)
            pairs = keys.map (key) -> { key: key, value: json[key] }

            current_time = new Date().getTime()
            sorted = pairs.sort((a, b) -> b.value - a.value)
            last_lan = sorted.find (p) -> p.value? and p.value < current_time

            if !!last_lan
                msg.send("#{restore(last_lan.key)} LAN was #{humanize(last_lan.value)} ago")
            else
                msg.send("I dunno when the last LAN was. I suck...")

    robot.hear /^(.+) lan countdown/i, (msg) ->
        lan_token = tokenize(msg.match[1])
        current_time = new Date().getTime()
        date = robot.brain.get(lan_token)

        if date >= current_time
            msg.send "#{restore(lan_token)} LAN in #{humanize(date)}"
        else
            msg.send "No LAN scheduled"

    robot.hear /^lan countdown/i, (msg) ->
        client = redis.createClient()
        client.get "hubot:storage", (error, reply) ->
            json = JSON.parse(reply.toString())
            keys = (match[0] for match in Object.keys(json["_private"]).map((key) -> key.match "^lan_(.+)") when !!match)
            pairs = keys.map (key) -> { key: key, value: robot.brain.get(key) }

            current_time = new Date().getTime()
            next_lan = pairs.sort((a, b) -> a.value - b.value).find (p) -> p.value >= current_time

            if !!next_lan
                msg.send("#{restore(next_lan.key)} LAN in #{humanize(next_lan.value)}")
            else
                msg.send("No upcoming LANs")

    robot.hear /^cancel (.+) lan/i, (msg) ->
        lan_token = tokenize(msg.match[1])
        robot.brain.set lan_token, null
        msg.send ":austin:"

char_replace = (str, prev, next) ->
  str.split(prev).join(next);

tokenize = (lan_name) ->
    "lan_#{char_replace(lan_name.trim(), ' ', '_').toLowerCase()}"

restore = (token) ->
    tokenized_name = token[4..-1]
    (word[0].toUpperCase() + word[1..-1].toLowerCase() for word in tokenized_name.split('_')).join ' '

humanize = (date) ->
    milli = date - new Date().getTime()
    humanize_duration(milli, { round: true, largest: 2 })
