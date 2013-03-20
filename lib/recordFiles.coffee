crypto = require( 'crypto' )
fs = require('fs');
path = require('path');
buffer = require('buffer');

sequence = 0

builtinGetBaseFileName = {
  sequence: (requestOptions, requestBody) ->
    return (sequence++).toString()
  hash: (requestOptions, requestBody) ->
    return crypto.createHash( "md5" ).update( requestOptions.host + requestOptions.path + requestBody).digest("hex")
}

getResponseBodyFileName = (requestOptions, requestBody, recordOptions) ->
  option = recordOptions.getResponseBaseFileName
  if ( typeof( option ) == 'function' )
    getResponseBaseFileName = option
  else if (typeof (option) == 'string' )
    getResponseBaseFileName = builtinGetBaseFileName[option]
  else
    getResponseBaseFileName = builtinGetBaseFileName.sequence

  filename = getResponseBaseFileName( requestOptions, requestBody ) + "-body"

  console.log('filename: ', filename)

  return filename

recordBodyToFile = (requestOptions, requestBody, responseBody, recordOptions) ->
  fileName = path.join(
    recordOptions.bodyPath, getResponseBodyFileName(requestOptions, requestBody, recordOptions))
  ws = fs.createWriteStream(fileName)
  buf = new buffer.Buffer(responseBody)

  ws.write(responseBody);
  ws.end();
  ws.destroy();

  return fileName

module.exports = {
  recordBodyToFile
}