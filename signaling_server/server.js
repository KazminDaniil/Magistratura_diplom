require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

//инициация сервера
const app = express();
app.use(cors());//разрешаем запросы с любых доменов
app.use(express.json());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
    transports: ["websocket", "polling"]
  }
});

//хранилище данных в памяти
const rooms = new Map();
const peerIdToSocketId = new Map();

//создание комнат
app.post('/api/room/create', (req, res) => {
  const roomCode = uuidv4().substring(0, 8).toUpperCase();
  rooms.set(roomCode, { id: roomCode, createdAt: new Date(), peers: [] });
  res.json({ success: true, roomCode, roomId: roomCode });
});

//проверка комнат
app.get('/api/room/:roomCode', (req, res) => {
  const { roomCode } = req.params;
  const room = rooms.get(roomCode.toUpperCase());
  if (room) {
    res.json({ exists: true, roomCode });
  } else {
    res.status(404).json({ exists: false, error: 'Комната не найдена' });
  }
});

//обработка реалтайм событий
io.on('connection', (socket) => {
  //вход в комнату
  socket.on('join_room', ({ roomCode, peerId }) => {
    const code = roomCode.toUpperCase();
    const room = rooms.get(code);
    
    if (!room) {
      socket.emit('error', { message: 'Комната не найдена' });
      return;
    }
    
    peerIdToSocketId.set(peerId, socket.id);
    
    socket.join(code);
    socket.data = { roomCode: code, peerId };
    
    socket.to(code).emit('peer_joined', { 
      peerId, 
      peers: room.peers.filter(p => p !== peerId)
    });
    
    if (!room.peers.includes(peerId)) {
      room.peers.push(peerId);
    }
    
    socket.emit('room_joined', {
      roomCode: code,
      peers: room.peers.filter(p => p !== peerId)
    });
  });
  //обмен sdp
  socket.on('signal', ({ to, from, signal, type }) => {
    const targetSocketId = peerIdToSocketId.get(to);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('signal', { from, signal, type });
    }
  });
  //обмен адресами
  socket.on('ice_candidate', ({ to, from, candidate }) => {
    const targetSocketId = peerIdToSocketId.get(to);
    
    if (targetSocketId) {
      io.to(targetSocketId).emit('ice_candidate', { from, candidate });
    }
  });
  //выход клиента
  socket.on('disconnecting', () => {
    const { roomCode, peerId } = socket.data || {};
    if (roomCode && peerId) {
      const room = rooms.get(roomCode);
      if (room) {
        room.peers = room.peers.filter(p => p !== peerId);
        socket.to(roomCode).emit('peer_left', { peerId });
      }
      peerIdToSocketId.delete(peerId);
    }
  });

  socket.on('disconnect', () => {
    for (const [pid, sid] of peerIdToSocketId.entries()) {
      if (sid === socket.id) {
        peerIdToSocketId.delete(pid);
        break;
      }
    }
  });
  //текстовый чат
  socket.on('chat_message', ({ roomCode, from, text, timestamp }) => {
    const code = roomCode.toUpperCase();
    const room = rooms.get(code);
    
    if (room && room.peers.includes(from)) {
      socket.to(code).emit('chat_message', { from, text, timestamp });
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => {
});