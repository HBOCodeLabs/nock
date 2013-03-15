var http = require('http');
var https = require('https');
var oldRequest = http.request;
var oldHttpsRequest = https.request;
var inspect = require('util').inspect;
var fs = require('fs');
var zlib = require('zlib');
var buffer = require('buffer');
var path = require('path');
var transformer = require('./transformer');
var recordFilter = require('./recordFilter');

var SEPARATOR = '\n<<<<<<-- cut here -->>>>>>\n';

var outputs = [];

var sequence = 0;

function baseFilenameForRequest(requestBody, options) {
  return (sequence++).toString();
}

function bodyFilenameForRequest(requestBody, options) {
    return baseFilenameForRequest(requestBody, options) + "-body";
}

function generateRequestAndResponse(body, options, res, datas, recordOptions, transformerNames, callback) {

  var requestBody = body.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  var responseBody = datas.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  var ret = [];
  ret.push('\nnock(\'');
  if (options._https_) {
    ret.push('https://');
  } else {
    ret.push('http://');
  }
  ret.push(options.host);
  if (options.port) {
    ret.push(':');
    ret.push(options.port);
  }
  ret.push('\')\n');
  ret.push('  .');
  ret.push((options.method || 'GET').toLowerCase());
  ret.push('(\'');
  ret.push(options.path);
  ret.push("'");
  if (requestBody) {
    ret.push(', ');
    ret.push(JSON.stringify(requestBody));
  }
  ret.push(")\n");

  if (recordOptions.recordBodiesToFiles === true) {
    ret.push('  .replyWithFile(');
  } else {
    ret.push('  .reply(');
  }
  ret.push(res.statusCode.toString());
  ret.push(', ');

  if (recordOptions.recordBodiesToFiles === true) {
    var fileName = path.join(
      recordOptions.bodyPath, bodyFilenameForRequest(requestBody, options));
    var ws = fs.createWriteStream(fileName); 
    var buf = new buffer.Buffer(responseBody);

    ws.write(responseBody);
    ws.end();
    ws.destroy();
    ret.push("\"");
    ret.push(fileName);
    ret.push("\"");
  } else {
    ret.push(JSON.stringify(responseBody));
  }

  if (res.headers) {
    ret.push(',\n  ');
    ret.push(inspect(res.headers));
  }

  if (transformerNames && transformerNames.length > 0) {
    ret.push(',\n  [ ');

    for (var i = (transformerNames.length - 1); i >= 0; i--) {
      ret.push("\"");
      ret.push(transformerNames[i]);
      ret.push("\"");
      if (i > 0) {
        ret.push(", ");
      }
    }
    ret.push(" ]");
  }

  ret.push(');\n');

  callback(ret.join(''));
}

function record(dont_print, recordOptions) {
  [http, https].forEach(function(module) {
    var oldRequest = module.request;
    module.request = function(options, callback) {

      var body = []
        , req, oldWrite, oldEnd;

      // A callback to determine whether or not we want to record this request/response
      var shouldRecord = recordFilter(options, recordOptions);

      req = oldRequest.call(http, options, function(res) {

        if (shouldRecord) {
          var transformerNames = [];

          // Apply transforms
          var recordedResponse = transformer.transformResponse(res, recordOptions, transformerNames);

          var datas = [];
          recordedResponse.on('data', function(data) {
            datas.push(data);
          });

          if (module === https) { options._https_ = true; }

          recordedResponse.once('end', function() {
            var out = generateRequestAndResponse(
              body, options, recordedResponse, datas, recordOptions, transformerNames, function(out) {
              outputs.push(out);
              if (! dont_print) { console.log(SEPARATOR + out + SEPARATOR); }
            });
          });
        }

        if (callback) {
          callback.apply(res, arguments);
        }
      });
      oldWrite = req.write;
      req.write = function(data) {
        if ('undefined' !== typeof(data)) {
          if (shouldRecord && data) {body.push(data); }
          oldWrite.call(req, data);
        }
      };
      return req;
    };

  });
}

function restore() {
  http.request = oldRequest;
  https.request = oldHttpsRequest;
}

function clear() {
  outputs = [];
}

exports.record = record;
exports.outputs = function() {
  return outputs;
};
exports.restore = restore;
exports.clear = clear;
