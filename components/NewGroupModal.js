'use client'
import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials, avatarColor } from '@/lib/chatFormat'

export default function NewGroupModal({ onClose }) {
  const router = useRouter()
  const { user, addChannel } = useChatStore()
  const [users, setUsers] = useState([])
  const [selected, setSelected] = useState([])
  const [name, setName] = useState('')
  const [q, setQ] = useState('')
  const [creating, setCreating] = useState(false)

  useEffect(() => {
    api.get('/users').then(({ data }) => {
      const list = Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : []
      setUsers(list.filter(u => u.id !== user?.id))
    }).catch(() => {})
  }, [user?.id])

  const toggle = (id) => setSelected(s => s.includes(id) ? s.filter(x => x !== id) : [...s, id])

  const create = async () => {
    if (!name.trim()) return toast.error('Enter a group name')
    if (selected.length === 0) return toast.error('Select at least one member')
    setCreating(true)
    try {
      const { data } = await api.post('/channels/group', { name: name.trim(), member_ids: selected })
      const channel = data?.data || data
      if (channel?.id) { addChannel(channel); router.push(`/chat/${channel.id}`) }
      onClose?.()
    } catch (e) { toast.error('Could not create group') } finally { setCreating(false) }
  }

  const filtered = users.filter(u => { const s = q.toLowerCase(); return !s || (u.name || '').toLowerCase().includes(s) })

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[15px] font-semibold text-white">New group</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-3 space-y-2">
          <input value={name} onChange={e => setName(e.target.value)} placeholder="Group name" className="w-full bg-[#202c33] rounded-lg px-3 py-2.5 text-sm text-white placeholder-gray-500 outline-none border-none" />
          <div className="flex items-center gap-2 bg-[#202c33] rounded-lg px-3 py-2">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#8696a0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
            <input value={q} onChange={e => setQ(e.target.value)} placeholder="Add members" className="bg-transparent border-none outline-none text-sm text-white placeholder-gray-500 w-full" />
          </div>
        </div>

        {selected.length > 0 && <div className="px-4 pb-1 text-[11px] text-brand-500">{selected.length} selected</div>}

        <div className="max-h-[42vh] overflow-y-auto px-2 pb-2">
          {filtered.map(u => {
            const on = selected.includes(u.id)
            return (
              <button key={u.id} onClick={() => toggle(u.id)} className="w-full flex items-center gap-3 p-2 rounded-lg hover:bg-[#202c33] text-left">
                <div className="h-10 w-10 rounded-full flex items-center justify-center text-white font-semibold text-sm flex-shrink-0" style={{ background: avatarColor(u.name) }}>{getInitials(u.name)}</div>
                <div className="min-w-0 flex-1"><div className="text-sm text-white truncate">{u.name}</div></div>
                <span className={`w-5 h-5 rounded-full border flex items-center justify-center flex-shrink-0 ${on ? 'bg-brand-500 border-brand-500' : 'border-gray-500'}`}>
                  {on && <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#06291f" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"/></svg>}
                </span>
              </button>
            )
          })}
          {filtered.length === 0 && <div className="text-center text-sm text-gray-500 py-6">No people found.</div>}
        </div>

        <div className="p-3 border-t border-white/10">
          <button onClick={create} disabled={creating} className="w-full bg-brand-500 text-[#06291f] font-semibold py-2.5 rounded-lg disabled:opacity-50">{creating ? 'Creating...' : 'Create group'}</button>
        </div>
      </div>
    </div>
  )
}