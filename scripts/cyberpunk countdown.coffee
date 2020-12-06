humanize_duration = require('humanize-duration')

module.exports = (robot) ->
  robot.hear /cyberpunk countdown/i, (res) ->
    date = new Date()
    date.setHours 19
    date.setMinutes 0
    date.setDate 9
    date.setMonth 11
    date.setFullYear 2020
    res.send "Cyberpunk in #{humanize date}\n Gird your loins"

humanize = (date) ->
    milli = date - new Date().getTime()
    humanize_duration(milli, { round: true, largest: 2 })