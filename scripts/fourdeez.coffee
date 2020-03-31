humanize_duration = require('humanize-duration')

module.exports = (robot) ->
  robot.hear /.*(four|40).*/i, (res) ->
    if thursday()
      res.send 'FOURDEEEEZZZZ!!'

  robot.hear /.*tonight.*/i, (msg) ->
    if thursday()
      unless /.*(tonight)( *)(tonight).*/i.exec msg.match
        msg.send 'tonight tonight*'

  robot.hear /40z countdown/i, (res) ->
    date = new Date()
    date.setHours 19
    date.setMinutes 30
    date.setDate(date.getDate() + ((7-date.getDay())%7+4) % 7)
    res.send "40z in #{humanize date}"

thursday = () ->
  new Date().getDay() == 4

humanize = (date) ->
    milli = date - new Date().getTime()
    humanize_duration(milli, { round: true, largest: 2 })