'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import Sidebar from '@/components/Sidebar'
import useChatStore from '@/store/chatStore'
import { getSocket, disconnectSocket } from '@/lib/socket'
import api from '@/lib/api'

function safeParseUser(value) {
  if (!value || value === 'undefined' || value === 'null') return null

  try {
    return JSON.parse(value)
  } catch {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('user')
    }
    return null
  }
}

export default function ChatLayout({ children }) {
  const router = useRouter()

  const {
    setUser,
    setChannels,
    addMessage,
    updateMessage,
    deleteMessage,
    updateReaction,
    setUserOnline,
    setUserOffline,
    setTyping,
  } = useChatStore()

  const [ready, setReady] = useState(false)

  useEffect(() => {
    const token = localStorage.getItem('token')

    if (!token || token === 'undefined' || token === 'null') {
      localStorage.removeItem('token')
      localStorage.removeItem('user')
      router.replace('/login')
      return
    }

    const savedUser = safeParseUser(localStorage.getItem('user'))
    if (savedUser) setUser(savedUser)

    const init = async () => {
      try {
        const [meRes, chRes] = await Promise.all([
          api.get('/auth/me'),
          api.get('/channels'),
        ])

        const userData = meRes.data?.data || meRes.data || null
        const channelsData = Array.isArray(chRes.data?.data)
          ? chRes.data.data
          : Array.isArray(chRes.data)
            ? chRes.data
            : []

        setUser(userData)
        setChannels(channelsData)

        if (userData) {
          localStorage.setItem('user', JSON.stringify(userData))
        }

        setReady(true)

        const socket = getSocket()

        if (socket) {
          socket.emit('join:channels')
          socket.on('message:new', msg => addMessage(msg.channel_id, msg))
          socket.on('message:edited', ({ message_id, channel_id, content }) => updateMessage(channel_id, message_id, { content, is_edited: 1 }))
          socket.on('message:deleted', ({ message_id, channel_id }) => deleteMessage(channel_id, message_id))
          socket.on('reaction:updated', ({ message_id, channel_id, emoji, user_id, action }) => updateReaction(channel_id, message_id, emoji, user_id, action))
          socket.on('user:online', ({ user_id }) => setUserOnline(user_id))
          socket.on('user:offline', ({ user_id }) => setUserOffline(user_id))
          socket.on('typing:start', ({ user_id, channel_id }) => setTyping(channel_id, user_id, true))
          socket.on('typing:stop', ({ user_id, channel_id }) => setTyping(channel_id, user_id, false))
        }
      } catch (error) {
        console.error('Chat init failed:', error)
        localStorage.removeItem('token')
        localStorage.removeItem('user')
        router.replace('/login')
      }
    }

    init()

    return () => disconnectSocket()
  }, [
    router,
    setUser,
    setChannels,
    addMessage,
    updateMessage,
    deleteMessage,
    updateReaction,
    setUserOnline,
    setUserOffline,
    setTyping,
  ])

  if (!ready) {
    return (
      <div className="min-h-screen bg-[#0f1117] text-white flex items-center justify-center">
        Loading chat...
      </div>
    )
  }

  return (
    <div className="flex min-h-screen bg-[#0f1117] text-white">
      <Sidebar />
      <main className="flex-1 overflow-hidden">{children}</main>
    </div>
  )
}
