_ = require 'underscore'
zlib = require 'zlib'

builtinTransformers =
  gzipTransformer:
    transformRecord: (response) ->
      if response.headers['content-encoding'] == 'gzip'
        transformed = new WrappedHttpResponse(response, pipeToGzip(response, zlib.createGunzip()))
        delete transformed.headers['content-encoding']
        delete transformed.headers['content-length']
        return transformed
      else
        return null
    transformPlayback: (response) ->
      transformed = new WrappedHttpResponse(response, pipeToGzip(response, zlib.createGzip()))
      response.headers['content-encoding'] = 'gzip'
      return transformed

  jsonTransformer:
    transformRecord: (response) ->
      if response.headers['content-type'].search('application/json') >= 0
        transformed = new StringTransformResponse response, (responseBody) ->
          parsedJSON = JSON.parse(responseBody)
          return JSON.stringify(parsedJSON, null, 2)
        delete transformed.headers['content-length']
        return transformed
      else
        return null
    transformPlayback: (response) ->
      transformed = new StringTransformResponse response, (responseBody) ->
        parsedJSON = JSON.parse(responseBody)
        return JSON.stringify(parsedJSON)
      return transformed

  doubleJsonTransformer:
    transformRecord: (response) ->
      transformed = new StringTransformResponse response, (responseBody) ->
        parsedJSON = JSON.parse(JSON.parse(responseBody))
        return JSON.stringify(parsedJSON, null, 2)
      delete transformed.headers['content-length']
      return transformed
    transformPlayback: (response) ->
      transformed = new StringTransformResponse response, (responseBody) ->
        parsedJSON = JSON.parse(responseBody);
        uglyJSON = JSON.stringify(JSON.stringify(parsedJSON))
        return uglyJSON
      return transformed

defaultTransformers = [
  'gzipTransformer',
  'jsonTransformer'
]


# Simualte/wrap a HTTP response with an alternate stream
class WrappedHttpResponse extends require('stream').Stream
  constructor: (@response, responseStream, headers) ->
    @readable = true
    @writable = false
    @headers = _.clone(headers ? @response.headers)
    if (response)
      @trailers = @response.trailers
      @statusCode = @response.statusCode
      @httpVersion = @response.httpVersion
    @responseStream = (responseStream) ? responseStream : @response

    @responseStream.on 'data', (data) =>
      @emit 'data', data
    @responseStream.on 'end', =>
      @emit 'end'
    @responseStream.on 'error', (exception)=>
      @emit 'error', exception
    @responseStream.on 'close', =>
      @emit 'close'
    
  pause: => @responseStream.pause()
  resume: => @responseStream.resume()
  setEncoding: (encoding) => @responseStream.setEncoding(encoding)

# A pipe that will read the entire input stream into a string, call a transform method, and
# emit the result as a stream
class StringTransformStream extends require('stream').Stream
  constructor: (@srcStream, @stringTransformer) ->
    @data = ''
    @readable = true
    @writable = true
  write: (chunk) =>
    @data += chunk
    return true
  end: (chunk) =>
    if chunk
      @data += chunk
    @emit 'data', @stringTransformer(@data)
    @emit 'end'
    return true
  pause: => @srcStream.pause()
  resume: => @srcStream.resume()
  setEncoding: (encoding) => @srcStream.setEncoding()

# This can be used to transform a stream into binary buffers (required by zlib)
class BufferTransformStream extends StringTransformStream
  constructor: (srcStream) ->
    super srcStream, (srcData) ->
      return new Buffer(srcData, 'binary')

# Wrap a HTTP response with a different result
class StringTransformResponse extends WrappedHttpResponse
  constructor: (response, stringTransformer) ->
    super(response, response.pipe(new StringTransformStream(response, stringTransformer)))

pipeToGzip = (srcStream, gzipperStream) ->
  bufStream = srcStream.pipe(new BufferTransformStream(srcStream))
  return bufStream.pipe(gzipperStream)

# Apply transforms and return the response to be recorded
transformRecordedResponse = (res, recordOptions, transformsUsed) ->
  responseTransformers = recordOptions.responseTransformers;
  if (!responseTransformers)
    responseTransformers = defaultTransformers
  recordedResponse = res
  if responseTransformers
    for transformerName in responseTransformers
      transformer = builtinTransformers[transformerName]
      transformedResponse = transformer.transformRecord(recordedResponse)
      if transformedResponse
        recordedResponse = transformedResponse;
        transformsUsed.push(transformerName);

  return recordedResponse

transformPlaybackResponse = (headers, body, responseTransformers) ->
  transformedResponse = new WrappedHttpResponse(null, body, headers)
  for transformerName in responseTransformers
    transformer = builtinTransformers[transformerName]
    transformedResponse = transformer.transformPlayback(transformedResponse)

  return transformedResponse

module.exports = {
  transformRecordedResponse,
  transformPlaybackResponse
}
