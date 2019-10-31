# Description:
#   None
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_APIXU_KEY Sign up at http://www.wunderground.com/weather/api/.
#   HUBOT_WUNDERGROUND_USE_METRIC Set to arbitrary value to use forecasts with metric system units
#
# Commands:
#   hubot weather me <location> - short-term forecast
#   hubot radar me <location> - recent radar image
#   hubot satellite me <location> - get a recent satellite image
#   hubot weathercam me <location> - get a weather webcam image near location
#
# Notes:
#   location can be zip code, ICAO/IATA airport code, state/city (CA/San_Franciso).
#
# Author:
#   alexdean

module.exports = (robot) ->
  robot.hear /^weather (ma|me|at|for|in)? ?(.*)$/i, (msg) ->
    location = msg.match[2]
    get_data robot, msg, location, 'forecast', location.replace(/\s/g, '_'), send_forecast, 60*60*2

  robot.hear /^temp (ma|me|at|for|in)? ?(.*)$/i, (msg) ->
    location = msg.match[2]
    get_data robot, msg, location, 'geolookup/conditions', location.replace(/\s/g, '_'), send_temp, 60*60*2    

  robot.hear /^radar (ma|me|at|for|in)? ?(.*)$/i, (msg) ->
    location = msg.match[2]
    get_data robot, msg, location, 'radar', location.replace(/\s/g, '_'), send_radar, 60*10

  robot.hear /^satellite (ma|me|at|for|in)? ?(.*)$/i, (msg) ->
    location = msg.match[2]
    get_data robot, msg, location, 'satellite', location.replace(/\s/g, '_'), send_satellite, 60*10

  robot.hear /^weathercam (ma|me|at|for|in)? ?(.*)$/i, (msg) ->
    location = msg.match[2]
    get_data robot, msg, location, 'webcams', location.replace(/\s/g, '_'), send_webcam, 60*30

  robot.hear /^fore (ma|me|at|for|in)? ?(.*)$/i, (msg) ->
    location = msg.match[2]
    get_data robot, msg, location, 'forecast', location.replace(/\s/g, '_'), send_long_forecast, 60*60*2

# check cache, get data, store data, invoke callback.
get_data = (robot, msg, location, service, query, cb, lifetime, stack=0) ->
  # what redis key to use
  cache_key = key_for service, location
  robot.brain.data.wunderground or= {}

  data = robot.brain.data.wunderground[cache_key]
  if data? and ttl(data) <= 0
    #console.log 'needs refresh'
    robot.brain.data.wunderground[cache_key] = data = null
  if data?
    #console.log 'cache is valid'
    cb msg, location, data, robot
  else
    if not process.env.HUBOT_APIXU_KEY?
      msg.send "HUBOT_APIXU_KEY is not set. Sign up at http://www.apixu.com"
      return
    # get new data
    msg
      .http("api.weatherstack.com/current?access_key=#{process.env.HUBOT_APIXU_KEY}&query=#{encodeURIComponent query}")
      .get() (err, res, body) ->
        # check for a non-200 response. cache it for some short amount of time && msg.send 'unavailable'
        if res.statusCode == 200
          data = JSON.parse(body)

          # probably an unknown place
          if data.response?.error?
            msg.send data.response.error.description

          # ambiguous place, multiple matches
          else if data.response?.results?
            alts = for key,item of data.response.results
              alternative_place item
            # we don't seem to have array.filter
            alts = for key,item of alts when item isnt ''
              item
            # if there's only 1 place, let's just get it.
            # stack: guard against infinite recursion
            if alts.length == 1 && stack == 0
              get_data robot, msg, location, service, alts[0], cb, lifetime, 1
            else
              msg.send "Possible matches for '#{location}'.\n - #{alts.join('\n - ')}"

          # looks good
          else
            robot.brain.data.wunderground[cache_key] = data
            robot.brain.data.wunderground[cache_key].retrieved = new Date
            robot.brain.data.wunderground[cache_key].lifetime = lifetime
            cb msg, location, robot.brain.data.wunderground[cache_key], robot
        else
          msg.send "api.weatherstack.com/current?access_key=#{process.env.HUBOT_APIXU_KEY}&query=#{encodeURIComponent query}"

send_temp = (msg, location, data) ->
  report = data['current']
  location = data['location']
  msg.send "#{report['condition'].text} and #{report.temp_f}°F (feels like #{report.feelslike_f}°F) with #{report.wind_mph}mph wind in #{location.name}"

send_forecast = (msg, location, data) ->
  report = data.forecast.txt_forecast.forecastday[0]
  useMetric = process.env.HUBOT_WUNDERGROUND_USE_METRIC?
  msg.send "#{report.title} in #{location}: #{if useMetric then report.fcttext_metric else report.fcttext} (#{formatted_ttl data})"

send_long_forecast = (msg, location, data, robot) ->
  report = data.forecast.txt_forecast.forecastday
  useMetric = process.env.HUBOT_WUNDERGROUND_USE_METRIC?
  for day in report
    robot.send {room: msg.envelope.user.name}, "#{day.title} in #{location}: #{if useMetric then day.fcttext_metric else day.fcttext} (#{formatted_ttl data})"

send_radar = (msg, location, data) ->
  msg.send "#{data.radar.image_url}#.png"

send_satellite = (msg, location, data) ->
  msg.send "#{data.satellite.image_url}#.png"

send_webcam = (msg, location, data) ->
  cam = msg.random data.webcams
  if cam?
    msg.send "#{cam.handle} in #{cam.city}, #{cam.state} (#{formatted_ttl data})"
    msg.send "#{cam.CURRENTIMAGEURL}#.png"
  else
    msg.send "No webcams near #{location}. (#{formatted_ttl data})"

# quick normalization to reduce caching of redundant data
key_for = (service, query) ->
  "#{service}-#{query.toLowerCase()}"

formatted_ttl = (data) ->
  parseInt(ttl(data)/1000)

# how long till our cached data expires?
ttl = (data) ->
  now = new Date
  if not data.lifetime? or not data.retrieved?
    -1
  else
    retrieved = Date.parse(data.retrieved)
    data.lifetime * 1000 - (now.getTime() - retrieved)

alternative_place = (item) ->
  return '' if item.country != 'US' || item.state == "" || item.city == ""
  return "#{item.state}/#{item.city.replace(/\s/g, '_')}"
