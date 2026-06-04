import { io } from 'socket.io-client';

let socket = null;

export const getSocket = () => {
  if (!socket && typeof window !== 'undefined') {
    const token = localStorage.getItem('token');
    const SOCKET_URL = process.env.NEXT_PUBLIC_SOCKET_URL || 'http://localhost:5000';

    socket = io(SOCKET_URL, {
      auth: { token },
      transports: ['polling', 'websocket'],
      withCredentials: true
    });

    socket.on('connect_error', (err) => {
      console.error('Socket connection error:', err.message);
    });
  }
  return socket;
};

export const connectSocket = getSocket;

export const disconnectSocket = () => {
  if (socket) {
    socket.disconnect();
    socket = null;
  }
};
