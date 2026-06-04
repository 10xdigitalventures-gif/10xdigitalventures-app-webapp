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
  const [filter, setFilter] = useState('all') // 'all', 'unread', 'groups'

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const { data } = await api.get('/users')
        setUsers(data.filter(u => u.id !== user?.id))
      } catch (err) {
        console.error('Failed to fetch users', err)
      }
    }
    fetchUsers()
  }, [user])

  const startDM = async (userId) => {
    try {
      const { data } = await api.post(`/channels/dm/${userId}`)
      addChannel(data)
      router.push(`/chat/${data.id}`)
    } catch (err) {
      toast.error('Could not start direct message')
    }
  }

  const logout = () => {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    router.replace('/login')
  }

  const filteredChats = channels.filter(ch => {
    const matchesSearch = ch.name.toLowerCase().includes(searchQuery.toLowerCase())
    if (filter === 'groups') return ch.type === 'public' || ch.type === 'private'
    if (filter === 'all') return matchesSearch
    return matchesSearch
  })

  return (
    <div className="w-[400px] bg-[#111b21] border-r border-[#222d34] flex flex-col h-screen flex-shrink-0">
      {/* Header */}
      <div className="p-4 bg-[#202c33] flex items-center justify-between">
        <div className="flex items-center gap-3 cursor-pointer" onClick={() => router.push('/profile')}>
          <div className="w-10 h-10 rounded-full bg-brand-500 flex items-center justify-center text-white font-bold">
            {user?.name?.[0]?.toUpperCase() || 'U'}
          </div>
          <div className="flex flex-col">
            <span className="text-white font-medium leading-tight">10x Chat Global v2.0</span>
            <span className="text-xs text-green-400">● Online</span>
          </div>
        </div>
        <div className="flex gap-4 text-gray-400">
          <button onClick={() => {}} className="hover:text-white">💬</button>
          <button onClick={logout} className="hover:text-white">↪</button>
        </div>
      </div>

      {/* Search & Filters */}
      <div className="p-3 space-y-3">
        <div className="relative">
          <input 
            type="text"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder="Search or start new chat"
            className="w-full pl-10 pr-4 py-2 bg-[#202c33] border-none rounded-lg text-sm text-white placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
          />
          <span className="absolute left-3 top-2.5 text-gray-500">🔍</span>
        </div>
        
        <div className="flex gap-2 overflow-x-auto pb-1">
          {['all', 'unread', 'groups'].map(f => (
            <button 
              key={f} 
              onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${filter === f ? 'bg-brand-500 text-white' : 'bg-[#202c33] text-gray-400 hover:bg-[#2a2d35]'}`}
            >
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      {/* Chat List */}
      <div className="flex-1 overflow-y-auto">
        {searchQuery && (
          <div className="px-4 py-2 bg-[#111b21]">
            <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Suggested Users</p>
            {users
              .filter(u => u.name.toLowerCase().includes(searchQuery.toLowerCase()) || u.email.toLowerCase().includes(searchQuery.toLowerCase()))
              .map(u => (
                <div 
                  key={u.id} 
                  onClick={() => startDM(u.id)}
                  className="flex items-center gap-3 p-3 cursor-pointer hover:bg-[#202c33] rounded-lg transition-colors group"
                >
                  <div className="w-12 h-12 rounded-full bg-brand-500 flex items-center justify-center text-white font-medium">
                    {u.name?.[0]?.toUpperCase()}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex justify-between items-center">
                      <span className="text-white font-medium truncate">{u.name}</span>
                      <span className="text-xs text-gray-500">Start Chat</span>
                    </div>
                    <p className="text-sm text-gray-400 truncate">Start a conversation with {u.name}</p>
                  </div>
                </div>
              ))
            }
          </div>
        )}

        <div className="divide-y divide-[#222d34]">
          {filteredChats.map(ch => (
            <Link key={ch.id} href={`/chat/${ch.id}`}>
              <div className={`flex items-center gap-3 p-3 cursor-pointer transition-colors ${activeChannelId === ch.id ? 'bg-[#2a3d45]' : 'hover:bg-[#202c33]'}`}>
                <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-medium ${ch.type === 'direct' ? 'bg-brand-500' : 'bg-gray-600'}`}>
                  {ch.name?.[0]?.toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex justify-between items-baseline">
                    <span className="text-white font-medium truncate">{ch.name}</span>
                    <span className="text-xs text-gray-500 ml-2">12:00 PM</span>
                  </div>
                  <p className="text-sm text-gray-400 truncate">Click to open chat</p>
                </div>
              </div>
            </Link>
          ))}
          {filteredChats.length === 0 && !searchQuery && (
            <div className="p-8 text-center text-gray-500 text-sm">
              No chats found. Start a new conversation!
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
