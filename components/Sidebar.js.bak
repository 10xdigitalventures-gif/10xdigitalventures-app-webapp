'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import toast from 'react-hot-toast'

export default function Sidebar({ activeChannelId }) {
  const router = useRouter()
  const { user, channels, addChannel } = useChatStore()
  const [searchQuery, setSearchQuery] = useState('')
  const [users, setUsers] = useState([])
  const [filter, setFilter] = useState('all')

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const { data } = await api.get('/users')
        const usersList = Array.isArray(data?.data)
          ? data.data
          : Array.isArray(data)
            ? data
            : []

        setUsers(usersList.filter(u => u.id !== user?.id))
      } catch (err) {
        console.error('Failed to fetch users', err)
      }
    }

    if (user?.id) fetchUsers()
  }, [user?.id])

  const startDM = async userId => {
    try {
      const { data } = await api.post(`/channels/dm/${userId}`)
      const channel = data?.data || data

      if (!channel?.id) {
        throw new Error('Invalid channel response')
      }

      addChannel(channel)
      router.push(`/chat/${channel.id}`)
    } catch (err) {
      toast.error('Could not start direct message')
    }
  }

  const logout = () => {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    router.replace('/login')
  }

  const safeChannels = Array.isArray(channels) ? channels : []

  const filteredChats = safeChannels.filter(ch => {
    const name = ch?.name || ''
    const matchesSearch = name.toLowerCase().includes(searchQuery.toLowerCase())

    if (filter === 'groups') return (ch.type === 'public' || ch.type === 'private') && matchesSearch
    return matchesSearch
  })

  const suggestedUsers = users.filter(u => {
    const name = u?.name || ''
    const email = u?.email || ''
    const q = searchQuery.toLowerCase()

    return name.toLowerCase().includes(q) || email.toLowerCase().includes(q)
  })

  return (
    <aside className="w-80 bg-[#111820] border-r border-white/10 flex flex-col min-h-screen">
      <div className="p-4 border-b border-white/10">
        <div className="flex items-center justify-between">
          <button onClick={() => router.push('/profile')} className="flex items-center gap-3 text-left">
            <div className="h-10 w-10 rounded-full bg-brand-500 flex items-center justify-center text-white font-bold">
              {user?.name?.[0]?.toUpperCase() || 'U'}
            </div>
            <div>
              <div className="text-white font-semibold">{user?.name || 'User'}</div>
              <div className="text-xs text-green-400">10x Chat Global v2.0 ● Online</div>
            </div>
          </button>

          <button onClick={logout} className="text-gray-400 hover:text-white">↪</button>
        </div>
      </div>

      <div className="p-4 space-y-3">
        <input
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          placeholder="Search or start new chat"
          className="w-full px-4 py-2 bg-[#202c33] border-none rounded-lg text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
        />

        <div className="flex gap-2">
          {['all', 'unread', 'groups'].map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
                filter === f ? 'bg-brand-500 text-white' : 'bg-[#202c33] text-gray-400 hover:bg-[#2a2d35]'
              }`}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-3 pb-4">
        {searchQuery && suggestedUsers.length > 0 && (
          <div className="mb-4">
            <div className="text-xs uppercase tracking-wide text-gray-500 px-2 mb-2">Suggested Users</div>

            {suggestedUsers.map(u => (
              <button
                key={u.id}
                onClick={() => startDM(u.id)}
                className="w-full flex items-center gap-3 p-3 cursor-pointer hover:bg-[#202c33] rounded-lg transition-colors text-left"
              >
                <div className="h-9 w-9 rounded-full bg-gray-700 flex items-center justify-center text-white font-bold">
                  {u.name?.[0]?.toUpperCase() || 'U'}
                </div>
                <div>
                  <div className="text-sm text-white">{u.name}</div>
                  <div className="text-xs text-gray-500">Start a conversation</div>
                </div>
              </button>
            ))}
          </div>
        )}

        <div className="space-y-1">
          {filteredChats.map(ch => (
            <Link
              key={ch.id}
              href={`/chat/${ch.id}`}
              className={`flex items-center gap-3 p-3 rounded-lg transition-colors ${
                activeChannelId === ch.id ? 'bg-brand-500/20 text-white' : 'text-gray-300 hover:bg-[#202c33]'
              }`}
            >
              <div className="h-10 w-10 rounded-full bg-[#202c33] flex items-center justify-center text-white font-bold">
                {ch.type === 'dm' ? ch.name?.[0]?.toUpperCase() : '#'}
              </div>

              <div className="min-w-0 flex-1">
                <div className="text-sm font-medium truncate">{ch.name}</div>
                <div className="text-xs text-gray-500 truncate">
                  {ch.topic || 'Click to open chat'}
                </div>
              </div>
            </Link>
          ))}

          {filteredChats.length === 0 && !searchQuery && (
            <div className="text-center text-sm text-gray-500 py-8">
              No chats found. Start a new conversation!
            </div>
          )}
        </div>
      </div>
    </aside>
  )
}
