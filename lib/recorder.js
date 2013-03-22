var http = require('http');
var https = require('https');
var oldRequest = http.request;
var oldHttpsRequest = https.request;
var inspect = require('util').inspect;
var buffer = require('buffer');
var transformer = require('./transformer');
var recordFilter = require('./recordFilter');
var recordFiles = require('./recordFiles');
var utilities = require('./utilities');

var SEPARATOR = '\n<<<<<<-- cut here -->>>>>>\n';

var outputs = [];

function generateRequestAndResponse(body, options, res, datas, recordOptions, transformerNames, callback) {

  var requestBody = body.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  var responseBody = datas.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  var ret = [];
  ret.push('\nnock(\'');
  ret.push(utilities.generateHostUrlString(options));
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
    recordFiles.recordBodyToFile(options, requestBody, responseBody, recordOptions, function(err, filename) {
      if (err) {
        console.error('error recording body to file: ', err);
        return;
      }
      ret.push("\"");
      ret.push(filename);
      ret.push("\"");
      generateHeadersAndTransformers(res, ret, transformerNames, callback);
    });
  } else {
    ret.push(JSON.stringify(responseBody));
    generateHeadersAndTransformers(res, ret, transformerNames, callback);
  }
}

function generateHeadersAndTransformers(res, ret, transformerNames, callback) {

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
          var recordedResponse = transformer.transformRecordedResponse(res, recordOptions, transformerNames);

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
