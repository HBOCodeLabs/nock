_ = require('underscore')
zlib = require('zlib')
Stream = require('stream').Stream

builtinTransformers =
  gzipTransformer:
    transformRecord: (response) ->
      if response.headers['content-encoding'] == 'gzip'
        transformed = new WrappedHttpResponse(response, new BufferEncodingStream(response, zlib.createGunzip()))
        delete transformed.headers['content-encoding']
        delete transformed.headers['content-length']
        return transformed
      else
        return null
    transformPlayback: (response) ->
      transformed = new WrappedHttpResponse(response, new BufferEncodingStream(response, zlib.createGzip()))
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

# Common functionality for a stream
class BaseStream extends Stream
  constructor: ->
    super()
    @readable = true
    @writable = true
  setEncoding: (encoding) =>
    @encoding = encoding

# Base class to pipe a stream while converting chunks
class ChunkTransformStream extends BaseStream
  constructor: (@convertChunk) ->
    super()
  write: (chunk) =>
    @emit 'data', @convertChunk(chunk, @encoding)
  end: (chunk) =>
    if chunk
      @write(chunk)
    @emit 'end'

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

# Stream to "wrap" another stream, while converting output to the correct type/encoding
class WrappedStream extends OutputStream
  constructor: (@srcStream) ->
    super()

  pause: => @srcStream.pause()
  resume: => @srcStream.resume()
  setEncoding: (encoding) =>
    super(encoding)
    @srcStream.setEncoding(encoding)
            
# Buffer encoding streams (gzip/gunzip) only handle Buffer data and do not pass through
# pause/resume calls.  Work around that here...
class BufferEncodingStream extends WrappedStream
  constructor: (srcStream, encodingStream) ->
    super(srcStream)
    @toBufferStream = new ToBufferStream()
    srcStream.pipe(@toBufferStream).pipe(encodingStream).pipe(this)
    
  setEncoding: (encoding) =>
    super(encoding)
    @toBufferStream.setEncoding(encoding)

# Base class to pipe a stream, converting/sending all the data at the end
class EndTransformStream extends BaseStream
  constructor: (@convertChunks) ->
    super()
    @chunks = []
  write: (chunk) =>
    @chunks.push(chunk)
  end: (chunk) =>
    if chunk
      @write(chunk)
    @emit @convertChunks(@chunks, @encoding)

# Base class to pipe a stream, converting/sending string data at the end
class EndStringTransformStream extends EndTransformStream
  constructor: (@stringTransform) ->
    super (chunks, encoding) ->
      data = ''
      for chunk in chunks
        data += convertToString(chunk)
      return @stringTransform(data, encoding)

# A pipe that will read the entire input stream into a string, call a transform method, and
# emit the result as a stream
class StringTransformStream extends WrappedStream
  constructor: (srcStream, stringTransformer) ->
    super(srcStream)
    @endStringTransformStream = new EndStringTransformStream(stringTransformer)
    srcStream.pipe(@endStringTransformStream).pipe(this)

  setEncoding: (encoding) =>
    super(encoding)
    @endStringTransformStream.setEncoding(encoding)

# Simualte/wrap a HTTP response with an alternate stream
class WrappedHttpResponse extends WrappedStream
  constructor: (response, responseStream, headers) ->
    wrappedStream = responseStream ? response
    super(wrappedStream)
    wrappedStream.pipe(this)
    @headers = _.clone(headers ? response.headers)
    if (response)
      @trailers = response.trailers
      @statusCode = response.statusCode
      @httpVersion = response.httpVersion

# Wrap a HTTP response with a different result
class StringTransformResponse extends WrappedHttpResponse
  constructor: (response, stringTransformer) ->
    super(response, response.pipe(new StringTransformStream(response, stringTransformer)))

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
