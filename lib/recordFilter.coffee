defaultRecordFilter = (options) ->
  return !((stringStartsWith(options.host, '127.0.0.1') ||
           (stringStartsWith(options.host, 'localhost'))))

stringStartsWith = (str, startingStr) ->
  return (str.indexOf(startingStr) == 0)

shouldRecord = (httpOptions, nockOptions) ->
  recordFilter = nockOptions?.recordFilter
  if (!recordFilter)
    recordFilter = defaultRecordFilter;
  # A callback to determine whether or not we want to record this request/response
  return recordFilter(httpOptions)
  
module.exports = shouldRecord