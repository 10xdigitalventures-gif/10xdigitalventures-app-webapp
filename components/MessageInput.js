'use client'
import { useState, useRef, useEffect } from 'react'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import api from '@/lib/api'

export default function MessageInput({ channelId }) {
  const [content, setContent] = useState('')
  const [uploading, setUploading] = useState(false)
  const [isTyping, setIsTyping] = useState(false)
  const fileInputRef = useRef(null)
  const typingTimeoutRef = useRef(null)

  const handleSend = () => {
    if (!content.trim()) return
    const socket = getSocket()
    socket.emit('message:send', {
      channel_id: channelId,
      content: content.trim(),
      type: 'text'
    })
    setContent('')
    stopTyping()
  }

  const startTyping = () => {
    if (!isTyping) {
      setIsTyping(true)
      const socket = getSocket()
      socket.emit('typing:start', { channel_id: channelId })
    }

    if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current)
    typingTimeoutRef.current = setTimeout(stopTyping, 3000)
  }

  const stopTyping = () => {
    setIsTyping(false)
    const socket = getSocket()
    socket.emit('typing:stop', { channel_id: channelId })
    if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current)
  }

  const handleFileUpload = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return

    setUploading(true)
    const formData = new FormData()
    formData.append('file', file)

    try {
      const { data } = await api.post(\`/files/upload/\${channelId}\`, formData)
      const socket = getSocket()
      socket.emit('message:send', {
        channel_id: channelId,
        content: data.data.file_name,
        type: data.data.type,
        file_url: data.data.file_url
      })
    } catch (err) {
      alert('Upload failed')
    } finally {
      setUploading(false)
      if (fileInputRef.current) fileInputRef.current.value = ''
    }
  }

  return (
    <div className="px-4 py-3 bg-[#12141a] border-t border-[#2a2d35] flex items-center gap-3">
      <input
        type="file"
        className="hidden"
        ref={fileInputRef}
        onChange={handleFileUpload}
      />

      <button
        onClick={() => fileInputRef.current?.click()}
        disabled={uploading}
        className="w-10 h-10 flex items-center justify-center rounded-full text-gray-400 hover:bg-white/5 transition-colors disabled:opacity-50"
      >
        <span className="text-xl">📎</span>
      </button>

      <div className="flex-1 relative">
        <textarea
          value={content}
          onChange={e => { setContent(e.target.value); startTyping() }}
          onKeyDown={e => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              handleSend()
            }
          }}
          placeholder="Type a message..."
          rows={1}
          className="resize-none py-3 px-4 pr-12 bg-[#1e2028] border-none focus:ring-0 text-[15px] max-h-32"
        />
        <button className="absolute right-3 top-1/2 -translate-y-1/2 text-lg grayscale hover:grayscale-0 transition-all">
          😊
        </button>
      </div>

      <button
        onClick={handleSend}
        disabled={!content.trim() || uploading}
        className="w-10 h-10 flex items-center justify-center rounded-full bg-brand-500 text-white transition-all hover:scale-105 active:scale-95 disabled:bg-gray-700 disabled:opacity-50 disabled:scale-100"
      >
        <span className="text-xl translate-x-0.5">🚀</span>
      </button>
    </div>
  )
}
