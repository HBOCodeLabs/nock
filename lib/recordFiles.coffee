crypto = require( 'crypto' )

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
    getResponseBaseFileName = builtinGetBaseFileName.hash

  filename = getResponseBaseFileName( requestOptions, requestBody ) + "-body"

  console.log('filename: ', filename)

  return filename

module.exports = {
  getResponseBodyFileName
}