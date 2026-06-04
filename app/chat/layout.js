'use client'
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import Sidebar from '@/components/Sidebar'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'

export default function ChatLayout({ children }) {
  const router = useRouter()
  const {
    setUser, setChannels,
    addMessage, updateMessage, deleteMessage,
    updateReaction, setUserOnline, setUserOffline, setTyping
  } = useChatStore()
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const token = localStorage.getItem('token')
    if (!token) { router.replace('/login'); return }
    const userStr = localStorage.getItem('user')
    const savedUser = userStr ? JSON.parse(userStr) : {}
    setUser(savedUser)

    const init = async () => {
      try {
        const [meRes, chRes] = await Promise.all([
          api.get('/auth/me'),
          api.get('/channels'),
        ])
        setUser(meRes.data)
        setChannels(chRes.data)
        setReady(true)

        const socket = getSocket()
        socket.emit('join:channels')

        socket.on('message:new', msg => addMessage(msg.channel_id, msg))
        socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
        socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
        socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
        socket.on('user:online', ({ user_id }) => setUserOnline(user_id))
        socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
        socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
        socket.on('typing:stop', ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
      } catch {
        router.replace('/login')
      }
    }

    init()
    return () => disconnectSocket()
  }, [])

  if (!ready) return (
    <div className="flex items-center justify-center h-screen bg-[#0f1117]">
      <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
    </div>
  )

  return (
    <div className="flex h-screen overflow-hidden bg-[#0f1117]">
      <Sidebar />
      {children}
    </div>
  )
}
