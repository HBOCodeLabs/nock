var http = require('http');
var https = require('https');
var oldRequest = http.request;
var oldHttpsRequest = https.request;
var inspect = require('util').inspect;
var crypto = require('crypto');
var fs = require('fs');
var zlib = require('zlib');
var buffer = require('buffer');

var SEPARATOR = '\n<<<<<<-- cut here -->>>>>>\n';

var outputs = [];

var sequence = 0;

function baseFilenameForRequest(requestBody, options) {
    // return crypto.createHash("md5").update(options.host + options.path + requestBody).digest("hex");
    sequence++;
    return sequence.toString();
}

function bodyFilenameForRequest(requestBody, options) {
    return baseFilenameForRequest(requestBody, options) + "-body";
}

function generateRequestAndResponse(body, options, res, datas, bodyPath, callback) {

  var requestBody = body.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  var responseBody = datas.map(function(buffer) {
    return buffer.toString('utf8');
  }).join('');

  if (res.headers['content-encoding'] != 'gzip') {
    generateRequestAndResponseDecoded(requestBody, responseBody, options, res, bodyPath, callback);
  } else {
    buf = new Buffer(responseBody, 'binary');
    zlib.gunzip(buf, function(err, body) {
      if (err) {
	console.log("Decoding error: ", err);
	generateRequestAndResponseDecoded(requestBody, responseBody, options, res, bodyPath, callback);
      } else {
	// Remove content-encoding header
	delete res.headers['content-encoding'];
	generateRequestAndResponseDecoded(requestBody, body.toString(), options, res, bodyPath, callback);
      }
    });
  }
}

function generateRequestAndResponseDecoded(requestBody, responseBody, options, res, bodyPath, callback) {

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

  if (! bodyPath) {
    ret.push('  .reply(');
  } else {
    ret.push('  .replyWithFile(');
  }
  ret.push(res.statusCode.toString());
  ret.push(', ');

  // TEMP reformat json
  if (res.headers['content-type'].search('application/json') >= 0) {
    var parsedJSON = JSON.parse(responseBody);
    responseBody = JSON.stringify(parsedJSON, null, 2);
  }

  if (! bodyPath) {
    ret.push(JSON.stringify(responseBody));
  } else {
    var fileName = bodyPath + "/" + bodyFilenameForRequest(requestBody, options);
    var ws = fs.createWriteStream(fileName); 
    var buf = new buffer.Buffer(responseBody);

    ws.write(responseBody);
    ws.end();
    ws.destroy();
    ret.push("\"");
    ret.push(fileName);
    ret.push("\"");
  }

  if (res.headers) {
    ret.push(',\n  ');
    ret.push(inspect(res.headers));
  }
  ret.push(');\n');

  callback(ret.join(''));
}

function record(dont_print, body_path) {
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
          var out = generateRequestAndResponse(body, options, res, datas, body_path, function(out) {
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
