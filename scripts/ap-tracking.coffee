mysql = require 'mysql'
# var mysql      = require('mysql');
# var connection = mysql.createConnection({
#   host     : 'localhost',
#   user     : 'me',
#   password : 'secret',
#   database : 'my_db'
# });

# connection.connect();

# connection.query('SELECT 1 + 1 AS solution', function(err, rows, fields) {
#   if (err) throw err;

#   console.log('The solution is: ', rows[0].solution);
# });

# connection.end();

module.exports = (robot) ->
  robot.hears /track ap start/, (msg) ->
    msg.send 'Bottoms up!'

  robot.hears /track ap stop/, (msg) ->
    msg.send "You haven't started drinking an AP"


connection = () ->
  @conn ||= mysql.createConnection
    host: 'localhost'
    user: ''
    password: ''
    database: ''