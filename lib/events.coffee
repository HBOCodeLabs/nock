events = require('events')

nockEvents = new events.EventEmitter()

emitNockEvent = (eventArguments...) ->
  nockEvents.emit eventArguments...

module.exports = { emitNockEvent, nockEvents }
