# Generate the host(:port) string from http request options
generateHostUrlString = (options) ->
  proto = null
  if options.proto is 'http'
    proto = 'http'
  else if options.proto is 'https'
    proto = 'https'
  else if options._https_ # Set by record in recorder.js
    proto = 'https'
  else
    proto = 'http'
    
  hostUrl = proto
  hostUrl += '://'
  hostUrl += options.host
  port = options.port ? if proto is 'http' then 80 else 443
  if options.host.indexOf(':') < 0
    hostUrl += ':'
    hostUrl += port
  return hostUrl

module.exports = { generateHostUrlString }
