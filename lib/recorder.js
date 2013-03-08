var http = require('http');
var https = require('https');
var oldRequest = http.request;
var oldHttpsRequest = https.request;
var inspect = require('util').inspect;
var fs = require('fs');
var zlib = require('zlib');
var buffer = require('buffer');
var path = require('path');

var SEPARATOR = '\n<<<<<<-- cut here -->>>>>>\n';

var outputs = [];

var sequence = 0;

function baseFilenameForRequest(requestBody, options) {
  return (sequence++).toString();
}

function bodyFilenameForRequest(requestBody, options) {
    return baseFilenameForRequest(requestBody, options) + "-body";
}

function copyProperties(source) {
  var dest = null;
  if (source) {
    dest = { };
    for (var key in source) {
      dest[key] = source[key];
    }
  }
  return dest;
}

function generateRequestAndResponse(body, options, res, datas, recordOptions, callback) {

  var requestBody = body.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  var responseBody = datas.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  // Make a copy of requestHeaders so that we can modify them...
  var responseHeaders = copyProperties(res.headers);

  if ((recordOptions.decompressGzipBodies === true) &&
      (res.headers['content-encoding'] === 'gzip')) {

    var buf = new Buffer(responseBody, 'binary');
    zlib.gunzip(buf, function(err, body) {
      if (err) {
	callback('**** Catastrophic error decoding gzip response: '+ err);
      } else {
	if (responseHeaders) {
	  delete responseHeaders['content-encoding'];
	  delete responseHeaders['content-length'];
	}
	generateRequestAndResponseDecoded(requestBody, body.toString(), options, res, responseHeaders, recordOptions, callback);
      }
    });
  } else {
    // Not unzipping...
    generateRequestAndResponseDecoded(requestBody, responseBody, options, res, responseHeaders, recordOptions, callback);
  }
}

function generateRequestAndResponseDecoded(requestBody, responseBody, options, res, responseHeaders, recordOptions, callback) {

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

  if (recordOptions.reformatJSON === true) {
    var contentType = responseHeaders['content-type'];
    
    if ((typeof(contentType) === 'string') &&
	(contentType.search('application/json') >= 0)) {
      var parsedJSON = JSON.parse(responseBody);
      responseBody = JSON.stringify(parsedJSON, null, 2);
      // Remove 'content-length' since we are changing the content
      delete responseHeaders['content-length'];
    }
  }

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

  if (responseHeaders) {
    ret.push(',\n  ');
    ret.push(inspect(responseHeaders));
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

      req = oldRequest.call(http, options, function(res) {
	var datas = [];

	res.on('data', function(data) {
          datas.push(data);
	});

	if (module === https) { options._https_ = true; }

	res.once('end', function() {
          var out = generateRequestAndResponse(body, options, res, datas, recordOptions, function(out) {
            outputs.push(out);
            if (! dont_print) { console.log(SEPARATOR + out + SEPARATOR); }
	  });
	});

	if (callback) {
          callback.apply(res, arguments);
	}

      });
      oldWrite = req.write;
      req.write = function(data) {
	if ('undefined' !== typeof(data)) {
          if (data) {body.push(data); }
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
