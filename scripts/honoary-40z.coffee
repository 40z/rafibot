humanize_duration = require('humanize-duration')
redis = require('redis')

module.exports = (robot) ->

    robot.hear /honorary 40z/i, (msg) ->
        members = robot.brain.get "honorary_40z_members"

        if members
            msg.send "Honorary 40z members:"
            for m, i in members
                msg.send m
        else
            msg.send "Nobody is honorable enough to stand among us"

    robot.hear /add honorary 40z member (.*)/i, (msg) ->
        members = robot.brain.get("honorary_40z_members") ? []
        members.push msg.match[1]
        robot.brain.set "honorary_40z_members", members

        msg.send "Dom bless #{msg.match[1]}"
