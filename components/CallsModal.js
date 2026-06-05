'use client'

import { useEffect, useState } from 'react'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials, avatarColor } from '@/lib/chatFormat'
import { useCall } from '@/context/CallContext'

export default function CallsModal({ onClose }) {
  const { user, onlineUsers } = useChatStore()
  const call = useCall()
  const [users, setUsers] = useState([])
  const [q, setQ] = useState('')

  useEffect(() => {
    api.get('/users').then(({ data }) => {
      const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
      setUsers(list.filter(u => u.id !== user?.id))
    }).catch(() => {})
  }, [user?.id])

  const placeCall = (u, type) => {
    if (!call?.startCall) return
    call.startCall(u.id, u.name, type)
    onClose?.()
  }

  const filtered = users.filter(u => {
    const s = q.toLowerCase()
    return !s || (u.name || '').toLowerCase().includes(s) || (u.email || '').toLowerCase().includes(s)
  })

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[15px] font-semibold text-white">Start a call</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-3">
          <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input autoFocus value={q} onChange={e => setQ(e.target.value)} placeholder="Search people" className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full" />
          </div>
        </div>

        <div className="max-h-[55vh] overflow-y-auto px-2 pb-3">
          {filtered.length === 0 ? (
            <div className="text-center text-sm text-gray-500 py-8">No people found.</div>
          ) : filtered.map(u => (
            <div key={u.id} className="flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33]">
              <div className="relative flex-shrink-0">
                <div className="h-11 w-11 rounded-full flex items-center justify-center text-white font-semibold text-sm" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                {onlineUsers?.has?.(u.id) && <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-brand-500 border-2 border-[#111820]" />}
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-sm text-white truncate">{u.name}</div>
                <div className="text-xs text-gray-500 truncate">{onlineUsers?.has?.(u.id) ? 'online' : 'offline'}</div>
              </div>
              <button onClick={() => placeCall(u, 'audio')} title="Voice call" aria-label="Voice call" className="w-9 h-9 flex items-center justify-center rounded-full text-brand-500 hover:bg-white/5">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>
              </button>
              <button onClick={() => placeCall(u, 'video')} title="Video call" aria-label="Video call" className="w-9 h-9 flex items-center justify-center rounded-full text-brand-500 hover:bg-white/5">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}