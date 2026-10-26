const http = require('http');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const port = 8899;
const types = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
};

http.createServer((request, response) => {
  const urlPath = decodeURIComponent((request.url || '/').split('?')[0]);
  const requested = urlPath === '/' ? '/index.html' : urlPath;
  const filePath = path.resolve(root, `.${requested}`);

  if (!filePath.startsWith(root + path.sep)) {
    response.writeHead(403).end('Forbidden');
    return;
  }

  fs.readFile(filePath, (error, file) => {
    if (error) {
      if (error.code === 'ENOENT') {
        fs.readFile(path.resolve(root, '404.html'), (notFoundError, notFoundFile) => {
          if (notFoundError) {
            response.writeHead(404).end('Not found');
            return;
          }
          response.writeHead(404, { 'Cache-Control': 'no-store', 'Content-Type': 'text/html; charset=utf-8' });
          response.end(notFoundFile);
        });
        return;
      }
      response.writeHead(500).end('Server error');
      return;
    }
    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': types[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
    });
    response.end(file);
  });
}).listen(port, '127.0.0.1', () => {
  console.log(`YGRIK.STUDIO: http://127.0.0.1:${port}`);
});
