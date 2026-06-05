'use client'

import { useState, useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import Link from 'next/link'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import toast from 'react-hot-toast'
import {
  formatChatTime, getInitials, avatarColor, sortChannels,
  previewOf, lastMsgStatus, lastMsgTime, peerId,
} from '@/lib/chatFormat'

const FILTERS = [
  { key: 'all', label: 'All' },
  { key: 'unread', label: 'Unread' },
  { key: 'groups', label: 'Groups' },
]

function PreviewIcon({ kind }) {
  const p = { width: 13, height: 13, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true }
  if (kind === 'image') return (<svg {...p}><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>)
  if (kind === 'video') return (<svg {...p}><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>)
  if (kind === 'voice') return (<svg {...p}><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/></svg>)
  if (kind === 'file') return (<svg {...p}><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>)
  return null
}

function Ticks({ status }) {
  if (!status) return null
  const c = status === 'read' ? '#34b7f1' : '#8696a0'
  if (status === 'sent') {
    return (<svg width="15" height="11" viewBox="0 0 16 12" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M2 6.5 5.5 10 13 2"/></svg>)
  }
  return (<svg width="17" height="11" viewBox="0 0 20 12" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M1 6.5 4.5 10 11.5 2"/><path d="M8 10 15 2"/></svg>)
}

export default function Sidebar() {
  const router = useRouter()
  const pathname = usePathname() || ''
  const activeChannelId = pathname.startsWith('/chat/') ? pathname.split('/chat/')[1]?.split('/')[0] : null

  const { user, channels, addChannel, onlineUsers } = useChatStore()
  const [searchQuery, setSearchQuery] = useState('')
  const [users, setUsers] = useState([])
  const [filter, setFilter] = useState('all')

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const { data } = await api.get('/users')
        const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
        setUsers(list.filter(u => u.id !== user?.id))
      } catch (err) {
        console.error('Failed to fetch users', err)
      }
    }
    if (user?.id) fetchUsers()
  }, [user?.id])

  const startDM = async (userId) => {
    try {
      const { data } = await api.post(`/channels/dm/${userId}`)
      const channel = data?.data || data
      if (!channel?.id) throw new Error('Invalid channel response')
      addChannel(channel)
      router.push(`/chat/${channel.id}`)
    } catch (err) {
      toast.error('Could not start direct message')
    }
  }

  const safeChannels = Array.isArray(channels) ? channels : []
  const q = searchQuery.toLowerCase()

  const visibleChannels = sortChannels(
    safeChannels.filter(ch => {
      const name = (ch?.name || '').toLowerCase()
      if (q && !name.includes(q)) return false
      if (filter === 'unread') return (ch.unread_count || 0) > 0
      if (filter === 'groups') return ch.type === 'public' || ch.type === 'private'
      return true
    })
  )

  const suggestedUsers = users.filter(u => {
    const name = (u?.name || '').toLowerCase()
    const email = (u?.email || '').toLowerCase()
    return name.includes(q) || email.includes(q)
  })

  return (
    <aside className="w-80 bg-[#111820] border-r border-white/10 flex flex-col h-screen">
      <div className="px-4 py-3 flex items-center justify-between">
        <span className="text-[17px] font-semibold text-white">Chats</span>
        <button title="New chat" aria-label="New chat" className="text-gray-400 hover:text-white">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4z"/></svg>
        </button>
      </div>

      <div className="px-3 pb-2">
        <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
          <input
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder="Search or start new chat"
            className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full"
          />
        </div>
      </div>

      <div className="flex gap-2 px-3 pb-2">
        {FILTERS.map(f => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-colors ${
              filter === f.key ? 'bg-brand-500 text-[#06291f]' : 'bg-[#202c33] text-gray-400 hover:bg-[#2a2d35]'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto px-2 pb-3">
        {q && suggestedUsers.length > 0 && (
          <div className="mb-2">
            <div className="text-[11px] uppercase tracking-wide text-gray-500 px-3 py-2">Start new chat</div>
            {suggestedUsers.map(u => (
              <button key={u.id} onClick={() => startDM(u.id)} className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33] text-left">
                <div className="h-11 w-11 rounded-full flex items-center justify-center text-white font-semibold text-sm flex-shrink-0" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                <div className="min-w-0">
                  <div className="text-sm text-white truncate">{u.name}</div>
                  <div className="text-xs text-gray-500 truncate">{u.email || 'Start a conversation'}</div>
                </div>
              </button>
            ))}
          </div>
        )}

        {visibleChannels.map(ch => {
          const isActive = activeChannelId === ch.id
          const isGroup = ch.type !== 'dm'
          const preview = previewOf(ch, user?.id)
          const status = lastMsgStatus(ch, user?.id)
          const unread = ch.unread_count || 0
          const time = formatChatTime(lastMsgTime(ch))
          const pid = peerId(ch)
          const online = !isGroup && pid && onlineUsers?.has?.(pid)

          return (
            <Link key={ch.id} href={`/chat/${ch.id}`} className={`flex items-center gap-3 px-2 py-1.5 rounded-lg transition-colors ${isActive ? 'bg-[#202c33]' : 'hover:bg-[#202c33]/60'}`}>
              <div className="relative flex-shrink-0">
                <div className="h-12 w-12 rounded-full flex items-center justify-center text-white font-semibold" style={{ background: isGroup ? '#2a3942' : avatarColor(ch.name) }}>
                  {isGroup ? (
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>
                  ) : getInitials(ch.name)}
                </div>
                {online && <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-brand-500 border-2 border-[#111820]" />}
              </div>

              <div className="min-w-0 flex-1 border-b border-white/5 pb-2">
                <div className="flex items-center justify-between gap-2">
                  <span className={`text-[15px] truncate ${unread ? 'text-white font-semibold' : 'text-gray-200'}`}>{ch.name}</span>
                  <span className={`text-[11px] flex-shrink-0 ${unread ? 'text-brand-500' : 'text-gray-500'}`}>{time}</span>
                </div>
                <div className="flex items-center justify-between gap-2 mt-0.5">
                  <span className="text-[12.5px] text-gray-500 truncate flex items-center min-w-0">
                    {status && <span className="mr-1 inline-flex flex-shrink-0"><Ticks status={status} /></span>}
                    {preview.sender && <span className="mr-1 flex-shrink-0">{preview.sender}:</span>}
                    {preview.kind !== 'text' && <span className="mr-1 inline-flex text-gray-400 flex-shrink-0"><PreviewIcon kind={preview.kind} /></span>}
                    <span className="truncate">{preview.text}</span>
                  </span>
                  <span className="flex items-center gap-1.5 flex-shrink-0">
                    {ch.is_muted && (
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M13.73 21a2 2 0 0 1-3.46 0"/><path d="M18.63 13A17.89 17.89 0 0 1 18 8"/><path d="M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14"/><path d="M18 8a6 6 0 0 0-9.33-5"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
                    )}
                    {ch.is_pinned && (
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="12" y1="17" x2="12" y2="22"/><path d="M5 17h14l-1.5-3V8a2 2 0 0 0-2-2h-7a2 2 0 0 0-2 2v6z"/></svg>
                    )}
                    {unread > 0 && (
                      <span className="bg-brand-500 text-[#06291f] text-[11px] font-semibold rounded-full min-w-[20px] h-5 flex items-center justify-center px-1.5">{unread > 99 ? '99+' : unread}</span>
                    )}
                  </span>
                </div>
              </div>
            </Link>
          )
        })}

        {visibleChannels.length === 0 && !q && (
          <div className="text-center text-sm text-gray-500 py-10">No chats yet. Search a name to start one.</div>
        )}
      </div>
    </aside>
  )
}