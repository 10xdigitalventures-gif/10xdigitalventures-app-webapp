'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import { getInitials } from '@/lib/chatFormat'

export default function SettingsModal({ onClose }) {
  const router = useRouter()
  const { user, setUser } = useChatStore()
  const [name, setName] = useState(user?.name || '')
  const [about, setAbout] = useState(user?.status || '')
  const [saving, setSaving] = useState(false)

  const save = async () => {
    if (!name.trim()) return toast.error('Name cannot be empty')
    setSaving(true)
    try {
      await api.put('/auth/profile', { name: name.trim(), status: about })
      const updated = { ...user, name: name.trim(), status: about }
      setUser(updated)
      localStorage.setItem('user', JSON.stringify(updated))
      toast.success('Saved')
    } catch (e) { toast.error('Could not save') } finally { setSaving(false) }
  }

  const enableNotifications = async () => {
    if (typeof Notification === 'undefined') return toast('Not supported')
    const p = await Notification.requestPermission()
    toast(p === 'granted' ? 'Notifications enabled' : 'Notifications blocked')
  }

  const logout = () => { localStorage.removeItem('token'); localStorage.removeItem('user'); router.replace('/login') }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center bg-black/60 pt-16" onClick={onClose}>
      <div className="w-full max-w-md bg-[#111820] rounded-xl border border-white/10 shadow-2xl overflow-hidden" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
          <span className="text-[15px] font-semibold text-white">Settings</span>
          <button onClick={onClose} aria-label="Close" className="text-gray-400 hover:text-white">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <div className="p-4 flex items-center gap-3 border-b border-white/10">
          <div className="h-14 w-14 rounded-full bg-brand-500 text-[#06291f] font-bold flex items-center justify-center text-lg">{getInitials(name)}</div>
          <div className="min-w-0">
            <div className="text-base font-semibold text-white truncate">{name || 'You'}</div>
            <div className="text-xs text-gray-500 truncate">{user?.email}</div>
          </div>
        </div>

        <div className="p-4 space-y-3">
          <div>
            <label className="block text-[11px] uppercase tracking-wide text-gray-500 mb-1">Name</label>
            <input value={name} onChange={e => setName(e.target.value)} className="w-full bg-[#202c33] rounded-lg px-3 py-2.5 text-sm text-white outline-none border-none" />
          </div>
          <div>
            <label className="block text-[11px] uppercase tracking-wide text-gray-500 mb-1">About</label>
            <input value={about} onChange={e => setAbout(e.target.value)} placeholder="Hey there! I am using 10x Chat" className="w-full bg-[#202c33] rounded-lg px-3 py-2.5 text-sm text-white placeholder-gray-500 outline-none border-none" />
          </div>
          <button onClick={save} disabled={saving} className="w-full bg-brand-500 text-[#06291f] font-semibold py-2.5 rounded-lg disabled:opacity-50">{saving ? 'Saving...' : 'Save changes'}</button>
        </div>

        <div className="border-t border-white/10 py-2">
          <button onClick={enableNotifications} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-white hover:bg-white/5 text-left">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
            Enable notifications
          </button>
          <button onClick={logout} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-red-400 hover:bg-white/5 text-left">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
            Log out
          </button>
        </div>
      </div>
    </div>
  )
}