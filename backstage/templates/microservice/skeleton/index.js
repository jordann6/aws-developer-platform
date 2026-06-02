const http = require('http');

const port = process.env.PORT || 8080;
const service = '${{ values.name }}';

const server = http.createServer((req, res) => {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', service }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ message: `hello from ${service}` }));
});

server.listen(port, () => console.log(`${service} listening on ${port}`));
