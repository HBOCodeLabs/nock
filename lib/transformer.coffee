_ = require('underscore')
zlib = require('zlib')
Stream = require('stream').Stream

builtinTransformers =
  gzipTransformer:
    transformRecord: (response) ->
      if response.headers['content-encoding'] == 'gzip'
        transformed = new WrappedHttpResponse(response, new GunzipEncodingStream(response))
        delete transformed.headers['content-encoding']
        delete transformed.headers['content-length']
        return transformed
      else
        return null
    transformPlayback: (response) ->
      transformed = new WrappedHttpResponse(response, new GzipEncodingStream(response))
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

# Convert to a string with specified encoding (by converting to a buffer and back)
convertToString = (data, srcEncoding, destEncoding) ->
  srcData = data
  if !Buffer.isBuffer(srcData)
    srcData = new Buffer(srcData, srcEncoding)
  return srcData.toString(destEncoding)

# Convert a string with the specified encoding to a buffer
convertToBuffer = (data, encoding) ->
  if !Buffer.isBuffer(data)
    return new Buffer(data, encoding)
  else
    return data

# Common functionality for a stream
class BaseStream extends Stream
  debugName: 'BaseStream'
  constructor: ->
    super()
    @readable = true
    @writable = true

  setEncoding: (encoding) =>
    @encoding = encoding

# Base class to pipe a stream while converting chunks
class ChunkTransformStream extends BaseStream
  debugName: 'ChunkTransformStream'
  constructor: (@convertChunk) ->
    super()
  write: (chunk, encoding) =>
    @emit 'data', @convertChunk(chunk, encoding ? @encoding, @encoding)
  end: (chunk) =>
    if chunk
      @write(chunk)
    @emit 'end'

# Stream to convert incomming data into appropriately encoded Buffer
# Need to do this before piping to zlib streams
class ToBufferStream extends ChunkTransformStream
  debugName: 'ToBufferStream'
  constructor: (srcEncodingDefault) ->
    super (data, srcEncodingWrite, destEncoding) ->
      srcEncoding = srcEncodingWrite ? srcEncodingDefault
      return convertToBuffer(data, srcEncoding)
      
# Stream to convert incomming data into appropriately encoded string
class OutputStream extends ChunkTransformStream
  debugName: 'OutputStream'
  constructor: ->
    super (data, srcEncoding, destEncoding) ->
      if destEncoding
        return convertToString(data, srcEncoding, destEncoding)
      else
        return convertToBuffer(data, srcEncoding)

# Stream to "wrap" another stream, while converting output to the correct type/encoding
class WrappedStream extends OutputStream
  debugName: 'WrappedStream'
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
  debugName: 'BufferEncodingStream'
  constructor: (srcStream, encodingStream, srcEncoding) ->
    super(srcStream)
    @toBufferStream = new ToBufferStream(srcEncoding)
    srcStream.pipe(@toBufferStream).pipe(encodingStream).pipe(this)
    
  setEncoding: (encoding) =>
    super(encoding)
    @toBufferStream.setEncoding(encoding)

class GzipEncodingStream extends BufferEncodingStream
  debugName: 'GzipEncodingStream'
  constructor: (srcStream) ->
    super(srcStream, zlib.createGzip())
    
class GunzipEncodingStream extends BufferEncodingStream
  debugName: 'GunzipEncodingStream'
  constructor: (srcStream) ->
    # HTTP response doesn't call write() with the encoding specified...but it is 'binary', so set that
    # as the default
    super(srcStream, zlib.createGunzip(), 'binary')

# Base class to pipe a stream, converting/sending all the data at the end
class EndTransformStream extends BaseStream
  debugName: 'EndTransformStream'
  constructor: (@convertChunks) ->
    super()
    @chunks = []
  write: (chunk, encoding) =>
    @chunks.push(chunk)
  end: (chunk, encoding) =>
    if chunk
      @write(chunk, encoding)
    @emit 'data', @convertChunks(@chunks, @encoding)
    @emit 'end'

# Base class to pipe a stream, converting/sending string data at the end
class EndStringTransformStream extends EndTransformStream
  debugName: 'EndStringTransformStream'
  constructor: (@stringTransform) ->
    super (chunks, encoding) ->
      data = ''
      for chunk in chunks
        data += convertToString(chunk, encoding, @encoding)
      return @stringTransform(data)

# A pipe that will read the entire input stream into a string, call a transform method, and
# emit the result as a stream
class StringTransformStream extends WrappedStream
  debugName: 'StringTransformStream'
  constructor: (srcStream, stringTransformer) ->
    super(srcStream)
    @endStringTransformStream = new EndStringTransformStream(stringTransformer)
    srcStream.pipe(@endStringTransformStream).pipe(this)

  setEncoding: (encoding) =>
    super(encoding)
    @endStringTransformStream.setEncoding(encoding)

# Simualte/wrap a HTTP response with an alternate stream
class WrappedHttpResponse extends WrappedStream
  debugName: 'WrappedHttpResponse'
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
  debugName: 'StringTransformResponse'
  constructor: (response, stringTransformer) ->
    super(response, new StringTransformStream(response, stringTransformer))

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
