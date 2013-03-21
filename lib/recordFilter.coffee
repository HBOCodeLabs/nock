defaultRecordFilter = (options) ->
  ((options.host != '127.0.0.1') && (options.host != 'localhost'))

shouldRecord = (httpOptions, recordOptions) ->
  recordFilter = recordOptions.recordFilter
  if (!recordFilter)
    recordFilter = defaultRecordFilter;
  # A callback to determine whether or not we want to record this request/response
  return recordFilter(httpOptions)
  
module.exports = shouldRecord