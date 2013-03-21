crypto = require('crypto')
fs = require('fs')
path = require('path')
buffer = require('buffer')

sequence = 0

builtinGetBaseFileName = {
  sequence: (requestOptions, requestBody) ->
    return (sequence++).toString()
  hash: (requestOptions, requestBody) ->
    return crypto.createHash('md5').update(requestOptions.host + requestOptions.path + requestBody).digest('hex')
}

getResponseBodyFileName = (requestOptions, requestBody, recordOptions) ->
  option = recordOptions.getResponseBaseFileName
  if (typeof(option) == 'function')
    getResponseBaseFileName = option
  else if (typeof (option) == 'string')
    getResponseBaseFileName = builtinGetBaseFileName[option]
  else
    getResponseBaseFileName = builtinGetBaseFileName.hash

  filename = getResponseBaseFileName(requestOptions, requestBody) + '-body'

  return filename

recordBodyToFile = (requestOptions, requestBody, responseBody, recordOptions, callback) ->
  fileName = path.join(
    recordOptions.bodyPath, getResponseBodyFileName(requestOptions, requestBody, recordOptions))

  checkForExistingFile fileName, responseBody, (err) ->
    if err
      callback(err, null)
      return

    ws = fs.createWriteStream(fileName)
    buf = new buffer.Buffer(responseBody)

    ws.write(responseBody);
    ws.end();
    ws.destroy();

    callback(null, fileName);
    return
  return

checkForExistingFile = (fileName, responseBody, callback) ->
  exists = fs.existsSync(fileName)
  if(!exists)
    callback(null)
    return

  rs = fs.createReadStream(fileName)
  
  # Allow an existing file, but only if the contents exactly match the requestBody
  compareStreamWithString rs, responseBody, (match) ->
    if ! match
      callback(new Error('Existing response body file does not match expected response: '+ fileName + ', : ' + responseBody))
    else
      callback(null)
    return
  return
  
compareStreamWithString = (rs, compareString, callback) ->
  rsString = ''
  rs.on 'data', (data) ->
    rsString += data
  rs.on 'end', ->
    callback(rsString == compareString)
  return

module.exports = {
  recordBodyToFile
}