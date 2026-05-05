# Real-Time Patterns — Claude Skill (Pro)

> Build real-time features. WebSockets, Socket.io, live notifications, presence, chat, collaborative editing. Node.js + React.

---

## Core Directives

1. **WebSocket is a transport, not architecture.** Use rooms, namespaces, and events — not raw messages.
2. **Authenticate connections.** Every WebSocket must verify the user's token on connect.
3. **Handle disconnects gracefully.** Users will lose connection — buffer, retry, and reconcile.
4. **Scale horizontally.** Use Redis adapter from day one — single-server WebSockets don't scale.

---

## 1 · Socket.io Setup

### Server
```typescript
import { Server as SocketServer } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient } from 'redis';
import { tokenService } from './modules/auth/token.service';

export function setupSocketIO(httpServer: HttpServer) {
  const io = new SocketServer(httpServer, {
    cors: { origin: env.ALLOWED_ORIGINS, credentials: true },
    pingTimeout: 60000,
    pingInterval: 25000,
  });

  // Redis adapter for horizontal scaling
  const pubClient = createClient({ url: env.REDIS_URL });
  const subClient = pubClient.duplicate();
  Promise.all([pubClient.connect(), subClient.connect()]).then(() => {
    io.adapter(createAdapter(pubClient, subClient));
  });

  // Auth middleware
  io.use(async (socket, next) => {
    const token = socket.handshake.auth.token;
    if (!token) return next(new Error('UNAUTHENTICATED'));
    try {
      const payload = tokenService.verifyAccessToken(token);
      socket.data.userId = payload.sub;
      socket.data.role = payload.role;
      next();
    } catch {
      next(new Error('INVALID_TOKEN'));
    }
  });

  io.on('connection', (socket) => {
    const userId = socket.data.userId;
    socket.join(`user:${userId}`);
    logger.info({ userId, socketId: socket.id }, 'Socket connected');

    // Join org rooms
    socket.on('join:org', async (orgId: string) => {
      const isMember = await Membership.exists({ user: userId, org: orgId });
      if (isMember) socket.join(`org:${orgId}`);
    });

    socket.on('disconnect', (reason) => {
      logger.debug({ userId, reason }, 'Socket disconnected');
    });
  });

  return io;
}
```

### Client (React)
```typescript
import { io, Socket } from 'socket.io-client';
import { useAuthStore } from '@/stores/auth';

let socket: Socket | null = null;

export function getSocket(): Socket {
  if (socket?.connected) return socket;

  const token = useAuthStore.getState().accessToken;

  socket = io(import.meta.env.VITE_WS_URL || '', {
    auth: { token },
    reconnection: true,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 5000,
    reconnectionAttempts: 10,
  });

  socket.on('connect_error', (err) => {
    if (err.message === 'INVALID_TOKEN') {
      // Token expired — refresh and reconnect
      useAuthStore.getState().refreshToken().then(() => {
        socket!.auth = { token: useAuthStore.getState().accessToken };
        socket!.connect();
      });
    }
  });

  return socket;
}

// React hook
export function useSocket(event: string, handler: (data: any) => void) {
  useEffect(() => {
    const s = getSocket();
    s.on(event, handler);
    return () => { s.off(event, handler); };
  }, [event, handler]);
}
```

---

## 2 · Live Notifications

### Server: Send Notification
```typescript
export async function sendNotification(io: SocketServer, notification: {
  recipientId: string;
  type: string;
  title: string;
  body: string;
  data?: Record<string, any>;
}) {
  // Persist to DB
  const saved = await Notification.create({
    recipient: notification.recipientId,
    type: notification.type,
    title: notification.title,
    body: notification.body,
    data: notification.data,
    read: false,
  });

  // Push via WebSocket
  io.to(`user:${notification.recipientId}`).emit('notification:new', {
    id: saved.id,
    type: saved.type,
    title: saved.title,
    body: saved.body,
    data: saved.data,
    createdAt: saved.createdAt,
  });
}

// Usage anywhere in your app:
await sendNotification(io, {
  recipientId: post.author,
  type: 'comment',
  title: 'New comment',
  body: `${commenter.name} commented on "${post.title}"`,
  data: { postId: post.id, commentId: comment.id },
});
```

### Client: Notification Hook
```tsx
export function useNotifications() {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);

  useSocket('notification:new', (notification) => {
    setNotifications(prev => [notification, ...prev]);
    setUnreadCount(c => c + 1);
    // Optional: browser notification
    if (Notification.permission === 'granted') {
      new Notification(notification.title, { body: notification.body });
    }
  });

  const markAsRead = async (id: string) => {
    await api.patch(`/notifications/${id}/read`);
    setNotifications(prev => prev.map(n => n.id === id ? { ...n, read: true } : n));
    setUnreadCount(c => Math.max(0, c - 1));
  };

  return { notifications, unreadCount, markAsRead };
}
```

---

## 3 · Presence (Online/Offline Status)

### Server
```typescript
const onlineUsers = new Map<string, Set<string>>(); // orgId → Set<userId>

io.on('connection', (socket) => {
  socket.on('presence:join', async (orgId: string) => {
    const userId = socket.data.userId;
    if (!onlineUsers.has(orgId)) onlineUsers.set(orgId, new Set());
    onlineUsers.get(orgId)!.add(userId);

    socket.join(`org:${orgId}`);
    io.to(`org:${orgId}`).emit('presence:update', {
      userId,
      status: 'online',
      onlineUsers: [...onlineUsers.get(orgId)!],
    });
  });

  socket.on('disconnect', () => {
    // Remove from all orgs
    for (const [orgId, users] of onlineUsers) {
      if (users.delete(socket.data.userId)) {
        io.to(`org:${orgId}`).emit('presence:update', {
          userId: socket.data.userId,
          status: 'offline',
          onlineUsers: [...users],
        });
      }
    }
  });
});
```

---

## 4 · Real-Time Chat

### Server Events
```typescript
socket.on('chat:message', async (data: { roomId: string; content: string }) => {
  const message = await Message.create({
    room: data.roomId,
    sender: socket.data.userId,
    content: data.content.trim().slice(0, 5000),
  });

  const populated = await message.populate('sender', 'name avatar');

  io.to(`room:${data.roomId}`).emit('chat:message', {
    id: message.id,
    content: message.content,
    sender: { id: populated.sender.id, name: populated.sender.name, avatar: populated.sender.avatar },
    createdAt: message.createdAt,
  });
});

socket.on('chat:typing', (data: { roomId: string }) => {
  socket.to(`room:${data.roomId}`).emit('chat:typing', {
    userId: socket.data.userId,
  });
});
```

---

## 5 · Event Patterns

### Emit Patterns
```typescript
// To specific user
io.to(`user:${userId}`).emit('event', data);

// To org/room
io.to(`org:${orgId}`).emit('event', data);

// To everyone except sender
socket.to(`org:${orgId}`).emit('event', data);

// Broadcast to all
io.emit('event', data);
```

### Event Naming Convention
```
namespace:action

notification:new
notification:read
chat:message
chat:typing
presence:update
document:change
cursor:move
```

---

## 6 · Scaling Checklist

```
✓ Redis adapter for multi-server (required for >1 instance)
✓ Authenticate on connection (verify JWT)
✓ Reconnection with exponential backoff (client-side)
✓ Room-based messaging (don't broadcast to all)
✓ Rate limit socket events (prevent spam)
✓ Persist critical events to DB (don't rely on socket delivery)
✓ Graceful shutdown (drain connections on SIGTERM)
✓ Monitor: active connections, events/sec, reconnection rate
✗ Don't store state only in socket memory (use Redis/DB)
✗ Don't send large payloads via WebSocket (use REST + notify)
```
