module.exports = (robot) ->
  robot.hear /.*(four|40).*/i, (res) ->
    if thursday()
      res.send 'FOURDEEEEZZZZ!!'

  robot.hear /.*tonight.*/i, (msg) ->
    if thursday()
      unless /.*(tonight)( *)(tonight).*/i.exec msg.match
        msg.send 'tonight tonight*'

thursday = () ->
  new Date().getDay() == 4