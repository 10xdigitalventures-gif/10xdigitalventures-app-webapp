'use client'
import { useState, useRef } from 'react'
import toast from 'react-hot-toast'
import { getSocket } from '@/lib/socket'
import api from '@/lib/api'

export default function MessageInput({ channelId }) {
  const [content, setContent] = useState('')
  const [uploading, setUploading] = useState(false)
  const [isTyping, setIsTyping] = useState(false)
  const [menuOpen, setMenuOpen] = useState(false)
  const mediaInputRef = useRef(null)
  const docInputRef = useRef(null)
  const typingTimeoutRef = useRef(null)

  const handleSend = () => {
    if (!content.trim()) return
    getSocket()?.emit('message:send', { channel_id: channelId, content: content.trim(), type: 'text' })
    setContent('')
    stopTyping()
  }

  const startTyping = () => {
    if (!isTyping) { setIsTyping(true); getSocket()?.emit('typing:start', { channel_id: channelId }) }
    if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current)
    typingTimeoutRef.current = setTimeout(stopTyping, 3000)
  }
  const stopTyping = () => {
    setIsTyping(false); getSocket()?.emit('typing:stop', { channel_id: channelId })
    if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current)
  }

  const uploadFile = async (file) => {
    if (!file) return
    setMenuOpen(false)
    setUploading(true)
    const formData = new FormData()
    formData.append('file', file)
    try {
      // The upload endpoint creates the message AND broadcasts it over the
      // socket (message:new). So we do NOT emit message:send here (doing both
      // caused duplicate + broken-image messages).
      await api.post(`/files/upload/${channelId}`, formData)
    } catch (err) {
      console.error('upload failed', err)
      toast.error('Upload failed')
    } finally {
      setUploading(false)
      if (mediaInputRef.current) mediaInputRef.current.value = ''
      if (docInputRef.current) docInputRef.current.value = ''
    }
  }

  return (
    <div className="px-4 py-3 bg-[#12141a] border-t border-[#2a2d35] flex items-center gap-3">
      <input type="file" accept="image/*,video/*" className="hidden" ref={mediaInputRef} onChange={e => uploadFile(e.target.files?.[0])} />
      <input type="file" className="hidden" ref={docInputRef} onChange={e => uploadFile(e.target.files?.[0])} />

      <div className="relative">
        <button onClick={() => setMenuOpen(o => !o)} disabled={uploading} title="Attach" aria-label="Attach"
          className="w-10 h-10 flex items-center justify-center rounded-full text-gray-400 hover:bg-white/5 transition-colors disabled:opacity-50">
          {uploading
            ? <span className="w-5 h-5 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
            : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>}
        </button>
        {menuOpen && (
          <div className="absolute bottom-12 left-0 w-52 bg-[#1e2229] border border-white/10 rounded-xl shadow-2xl overflow-hidden z-20">
            <button onClick={() => mediaInputRef.current?.click()} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-white hover:bg-white/5 text-left">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>
              Photos & Videos
            </button>
            <button onClick={() => docInputRef.current?.click()} className="w-full flex items-center gap-3 px-4 py-3 text-sm text-white hover:bg-white/5 text-left">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1db791" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
              Document
            </button>
          </div>
        )}
      </div>

      <div className="flex-1">
        <textarea
          value={content}
          onChange={e => { setContent(e.target.value); startTyping() }}
          onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
          placeholder="Type a message..."
          rows={1}
          className="w-full resize-none py-3 px-4 bg-[#1e2028] rounded-2xl border-none focus:ring-0 text-[15px] text-white placeholder-gray-500 max-h-32"
        />
      </div>

      <button onClick={handleSend} disabled={!content.trim() || uploading} title="Send" aria-label="Send"
        className="w-10 h-10 flex items-center justify-center rounded-full bg-brand-500 text-[#06291f] transition-all hover:scale-105 active:scale-95 disabled:bg-gray-700 disabled:opacity-50 disabled:scale-100">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>
      </button>
    </div>
  )
}