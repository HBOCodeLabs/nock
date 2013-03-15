_ = require 'underscore'

# Wrap an HTTP response with alternate headers and an alternate stream
class RecordedResponse extends require('stream')
  constructor: (@response) ->
    super()
    this.headers = _.clone(@response.headers)
    this.trailers = @response.trailers
    this.statusCode = @response.statusCode
    this.httpVersion = @response.httpVersion

  setEncoding: (encoding) => @response.setEncoding(encoding)

module.exports = RecordedResponse
