var express = require('express')
var path = require('path')
var {ufs} = require('unionfs')
var express = require('express')
var {pathToAbsolute, makeIndexJson} = require('./content.js')
var {sendCompressed} = require('./compress.js')

var app = express()
express.static.mime.types['wasm'] = 'application/wasm'

function pathToDirectoryIndex(url) {
  const parsed = new URL(`https://local${url}`)
  var absolute = pathToAbsolute(parsed.pathname)
  // return index.json for directories or return a file out of baseq3
  var filename
  if(absolute
    && ufs.existsSync(absolute)
    && ufs.statSync(absolute).isDirectory()) {
    filename = path.join(parsed.pathname, 'index.json')
    absolute = pathToAbsolute(filename)
  } else if (absolute
    && ufs.existsSync(path.dirname(absolute))
    && ufs.statSync(path.dirname(absolute)).isDirectory()
    && parsed.pathname.match(/\/index\.json$/ig)) {
    filename = parsed.pathname
  }
  return {filename, absolute}
}

async function serveUnionFs(req, res, next) {
  var {filename, absolute} = pathToDirectoryIndex(req.url)
  if(filename) {
    await makeIndexJson(filename, absolute)
  }
  if (absolute && ufs.existsSync(absolute)) {
    sendCompressed(absolute, res, false) //req.headers['accept-encoding'].includes('gzip'))
  } else {
    console.log(`Couldn't find file "${req.url}" "${absolute}".`)
		next()
	}
}

app.use('/', express.static(path.join(__dirname), { extensions: ['html'] }))
app.use('/', express.static(path.join(__dirname, '../../../build/release-js-js'), { extensions: ['wasm'] }))
app.use(serveUnionFs)

app.listen(8080)
