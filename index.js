var recorder = require('./lib/recorder')
var events = require('./lib/events')
module.exports = require('./lib/scope');

module.exports.recorder = {
    rec  : recorder.record
  , clear   : recorder.clear
  , play : recorder.outputs
};
module.exports.restore = recorder.restore;
module.exports.events = events.nockEvents;
