const WebSocket = require('ws');
const http = require('http');

const PORT = 8080;

// Create HTTP server
const server = http.createServer();

// Create WebSocket server
const wss = new WebSocket.Server({ server });

// Store connected clients
const clients = new Set();

wss.on('connection', (ws, req) => {
  console.log('New client connected from:', req.socket.remoteAddress);
  clients.add(ws);

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());
      console.log('Received motion data:', message);
      
      // Broadcast to all other clients (web browsers)
      clients.forEach(client => {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify(message));
        }
      });
    } catch (error) {
      console.error('Error parsing message:', error);
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
    clients.delete(ws);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    clients.delete(ws);
  });

  // Send welcome message
  ws.send(JSON.stringify({
    type: 'welcome',
    message: 'Connected to 3D Mouse Server'
  }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`3D Mouse Server running on port ${PORT}`);
  console.log(`WebSocket URL: ws://localhost:${PORT}`);
  console.log('Make sure to update the IP address in the mobile app!');
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down server...');
  wss.close(() => {
    server.close(() => {
      process.exit(0);
    });
  });
});