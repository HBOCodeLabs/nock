_ = require('underscore')
zlib = require('zlib')
Stream = require('stream').Stream

builtinTransformers =
  gzipTransformer:
    transformRecord: (response) ->
      if response.headers['content-encoding'] == 'gzip'
        transformed = new WrappedHttpResponse(response, new BinaryEncodingStream(response, zlib.createGunzip()))
        delete transformed.headers['content-encoding']
        delete transformed.headers['content-length']
        return transformed
      else
        return null
    transformPlayback: (response) ->
      transformed = new WrappedHttpResponse(response, new BinaryEncodingStream(response, zlib.createGzip()))
      transformed.headers['content-encoding'] = 'gzip'
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
class WrappedHttpResponse extends Stream
  constructor: (@response, responseStream, headers) ->
    @readable = true
    @writable = false
    @headers = _.clone(headers ? @response.headers)
    if (response)
      @trailers = @response.trailers
      @statusCode = @response.statusCode
      @httpVersion = @response.httpVersion
    @responseStream = responseStream ? @response

    @responseStream.on 'data', (data) =>
      @emit 'data', data
    @responseStream.on 'end', =>
      @emit 'end'
    @responseStream.on 'error', (exception)=>
      @emit 'error', exception
    
  pause: => @responseStream.pause()
  resume: => @responseStream.resume()
  setEncoding: (encoding) => @responseStream.setEncoding(encoding)

# A pipe that will read the entire input stream into a string, call a transform method, and
# emit the result as a stream
class StringTransformStream extends Stream
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
  pause: =>
    @srcStream.pause()
  resume: =>
    @srcStream.resume()
  setEncoding: (encoding) =>
    @srcStream.setEncoding()

# Wrap a HTTP response with a different result
class StringTransformResponse extends WrappedHttpResponse
  constructor: (response, stringTransformer) ->
    super(response, response.pipe(new StringTransformStream(response, stringTransformer)))

# Base class to pipe a stream while converting chunks
class ChunkTransformStream extends Stream
  constructor: (@convertChunk) ->
    @readable = true
    @writable = true
  write: (chunk) =>
    @emit 'data', @convertChunk(chunk, @encoding)
  end: (chunk) =>
    if chunk
      @write(chunk)
    @emit 'end'
  setEncoding: (encoding) =>
    @encoding = encoding

# Stream to convert incomming data into appropriately encoded Buffer
# Need to do this before piping to zlib streams
class ToBufferStream extends ChunkTransformStream
  constructor: ->
    super (data, encoding) ->
      return convertToBuffer(data, encoding)

# Stream to convert incomming data into appropriately encoded string
class OutputStream extends ChunkTransformStream
  constructor: ->
    super (data, encoding) ->
      if encoding
        return convertToString(data, encoding)
      else
        return convertToBuffer(data, encoding)

convertToString = (data, encoding) ->
  if Buffer.isBuffer(data)
    return data.toString(encoding)
  else
    return data.toString()

convertToBuffer = (data, encoding) ->
  if !Buffer.isBuffer(data)
    return new Buffer(data, encoding)
  else
    return data
    
# Binary encoding streams (gzip/gunzip) only handle Buffer data and do not pass through
# pause/resume calls.  Work around that here
class BinaryEncodingStream extends OutputStream
  constructor: (@srcStream, encodingStream) ->
    super()
    @toBufferStream = new ToBufferStream()
    @srcStream.pipe(@toBufferStream).pipe(encodingStream).pipe(this)
    
  pause: =>
    @srcStream.pause()
  resume: =>
    @srcStream.resume()
  setEncoding: (encoding) =>
    super(encoding)
    @srcStream.setEncoding(encoding)
    @toBufferStream.setEncoding(encoding)

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
