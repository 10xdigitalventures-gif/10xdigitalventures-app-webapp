'use client'
import { createContext, useContext, useState, useEffect, useCallback } from 'react'
import { connectSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'

const ChatContext = createContext(null)

export function ChatProvider({ children }) {
  const [channels, setChannels] = useState([])
  const [users, setUsers] = useState([])
  const [activeChannel, setActiveChannel] = useState(null)
  const [messages, setMessages] = useState({})
  const [typingUsers, setTypingUsers] = useState({})
  const [socket, setSocket] = useState(null)
  const [onlineUsers, setOnlineUsers] = useState(new Set())

  useEffect(() => {
    loadChannels()
    loadUsers()
    const s = connectSocket()
    setSocket(s)

    s.on('message:new', (msg) => {
      setMessages(prev => ({
        ...prev,
        [msg.channel_id]: [...(prev[msg.channel_id] || []), msg]
      }))
    })

    s.on('message:edited', ({ message_id, content }) => {
      setMessages(prev => {
        const updated = {}
        for (const [cid, msgs] of Object.entries(prev)) {
          updated[cid] = msgs.map(m => m.id === message_id ? { ...m, content, is_edited: 1 } : m)
        }
        return updated
      })
    })

    s.on('message:deleted', ({ message_id }) => {
      setMessages(prev => {
        const updated = {}
        for (const [cid, msgs] of Object.entries(prev)) {
          updated[cid] = msgs.filter(m => m.id !== message_id)
        }
        return updated
      })
    })

    s.on('reaction:updated', ({ message_id, user_id, emoji, action }) => {
      setMessages(prev => {
        const updated = {}
        for (const [cid, msgs] of Object.entries(prev)) {
          updated[cid] = msgs.map(m => {
            if (m.id !== message_id) return m
            let reactions = m.reactions ? [...m.reactions] : []
            if (action === 'added') reactions.push({ emoji, user_id })
            else reactions = reactions.filter(r => !(r.emoji === emoji && r.user_id === user_id))
            return { ...m, reactions }
          })
        }
        return updated
      })
    })

    s.on('typing:start', ({ user_id, channel_id }) => {
      setTypingUsers(prev => ({
        ...prev,
        [channel_id]: [...new Set([...(prev[channel_id] || []), user_id])]
      }))
    })

    s.on('typing:stop', ({ user_id, channel_id }) => {
      setTypingUsers(prev => ({
        ...prev,
        [channel_id]: (prev[channel_id] || []).filter(id => id !== user_id)
      }))
    })

    s.on('user:online', ({ user_id }) => {
      setOnlineUsers(prev => new Set([...prev, user_id]))
    })

    s.on('user:offline', ({ user_id }) => {
      setOnlineUsers(prev => { const n = new Set(prev); n.delete(user_id); return n })
    })

    return () => disconnectSocket()
  }, [])

  const loadChannels = async () => {
    try {
      const { data } = await api.get('/channels')
      setChannels(data)
    } catch {}
  }

  const loadUsers = async () => {
    try {
      const { data } = await api.get('/users')
      setUsers(data)
      setOnlineUsers(new Set(data.filter(u => u.is_online).map(u => u.id)))
    } catch {}
  }

  const loadMessages = useCallback(async (channelId) => {
    if (messages[channelId]) return
    try {
      const { data } = await api.get(`/messages/${channelId}`)
      setMessages(prev => ({ ...prev, [channelId]: data }))
    } catch {}
  }, [messages])

  const sendMessage = (channelId, content, replyTo = null) => {
    if (!socket) return
    socket.emit('message:send', { channel_id: channelId, content, reply_to: replyTo })
  }

  const editMessage = (channelId, messageId, content) => {
    socket?.emit('message:edit', { channel_id: channelId, message_id: messageId, content })
  }

  const deleteMessage = (channelId, messageId) => {
    socket?.emit('message:delete', { channel_id: channelId, message_id: messageId })
  }

  const toggleReaction = (channelId, messageId, emoji) => {
    socket?.emit('reaction:toggle', { channel_id: channelId, message_id: messageId, emoji })
  }

  const startTyping = (channelId) => socket?.emit('typing:start', { channel_id: channelId })
  const stopTyping = (channelId) => socket?.emit('typing:stop', { channel_id: channelId })

  const createChannel = async (name, type = 'public') => {
    const { data } = await api.post('/channels', { name, type })
    setChannels(prev => [...prev, data])
    return data
  }

  return (
    <ChatContext.Provider value={{
      channels, users, activeChannel, setActiveChannel,
      messages, typingUsers, onlineUsers,
      loadMessages, sendMessage, editMessage, deleteMessage,
      toggleReaction, startTyping, stopTyping,
      createChannel, loadChannels
    }}>
      {children}
    </ChatContext.Provider>
  )
}

export const useChat = () => useContext(ChatContext)
