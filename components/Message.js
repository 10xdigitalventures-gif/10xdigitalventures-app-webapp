'use client'
import { useState, useEffect, useRef } from 'react'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { mediaUrl } from '@/lib/chatFormat'

// Clean WhatsApp-style reaction set (ASCII source -- built from code points)
const QUICK_EMOJI_CP = [
  [0x1F44D],          // thumbs up
  [0x2764, 0xFE0F],   // red heart
  [0x1F602],          // joy
  [0x1F62E],          // open mouth (wow)
  [0x1F625],          // sad
  [0x1F64F],          // folded hands (thanks)
]
const QUICK_EMOJIS = QUICK_EMOJI_CP.map(p => String.fromCodePoint(...p))

// Extra set shown when user clicks "+"
const MORE_EMOJI_CP = [
  [0x1F525],[0x1F44F],[0x1F389],[0x1F923],[0x1F60D],[0x1F914],
  [0x1F44C],[0x1F4AF],[0x1F60A],[0x1F622],[0x1F621],[0x1F44B],
  [0x2705],[0x274C],[0x1F4AA],[0x1F440],[0x1F31F],[0x1F381]
]
const MORE_EMOJIS = MORE_EMOJI_CP.map(p => String.fromCodePoint(...p))

const timeFormatter = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })

function fmtSize(bytes) {
  if (!bytes) return ''
  const kb = bytes / 1024
  return kb < 1024 ? `${Math.round(kb)} KB` : `${(kb / 1024).toFixed(1)} MB`
}

function TickSingle({ color }) {
  return (
    <svg width="15" height="11" viewBox="0 0 16 11" fill="none" aria-hidden="true">
      <path d="M1 5.5L5.5 10L15 1" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  )
}
function TickDouble({ color }) {
  return (
    <svg width="18" height="11" viewBox="0 0 20 11" fill="none" aria-hidden="true">
      <path d="M1 5.5L5 9.5L13 1" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M7 5.5L11 9.5L19 1" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  )
}
function SmileIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/>
    </svg>
  )
}
function PencilIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/>
    </svg>
  )
}
function TrashIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/>
    </svg>
  )
}

// ---------- Reaction Picker (persistent until outside click) ----------
function ReactionPicker({ alignRight, onPick, onClose }) {
  const ref = useRef(null)
  const [showMore, setShowMore] = useState(false)
  useEffect(() => {
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) onClose()
    }
    // Defer registration so the same click that opened it doesn't immediately close it
    const t = setTimeout(() => document.addEventListener('mousedown', handler), 0)
    return () => { clearTimeout(t); document.removeEventListener('mousedown', handler) }
  }, [onClose])

  return (
    <div
      ref={ref}
      className={`absolute bottom-full mb-2 z-50 ${alignRight ? 'right-0' : 'left-0'}`}
    >
      <div className="bg-[#1f2c33] border border-white/10 rounded-full px-2 py-1.5 flex items-center gap-1 shadow-2xl animate-fade-in">
        {QUICK_EMOJIS.map(e => (
          <button key={e} onClick={() => onPick(e)} className="w-8 h-8 flex items-center justify-center hover:scale-125 transition-transform text-[20px] leading-none">{e}</button>
        ))}
        <button onClick={() => setShowMore(v => !v)} title="More" className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-white/10 text-white/80 text-lg">+</button>
      </div>
      {showMore && (
        <div className="mt-2 bg-[#1f2c33] border border-white/10 rounded-2xl p-2 shadow-2xl grid grid-cols-6 gap-1 w-[260px] animate-fade-in">
          {MORE_EMOJIS.map(e => (
            <button key={e} onClick={() => onPick(e)} className="w-9 h-9 flex items-center justify-center hover:scale-125 transition-transform text-[20px] leading-none">{e}</button>
          ))}
        </div>
      )}
    </div>
  )
}

export default function Message({ msg, channelId }) {
  const { user, updateMessage, deleteMessage, updateReaction } = useChatStore()
  const [showActions, setShowActions] = useState(false)
  const [editing, setEditing] = useState(false)
  const [editContent, setEditContent] = useState(msg.content)
  const [showPicker, setShowPicker] = useState(false)

  const isOwn = msg.sender_id === user?.id
  const isDeleted = msg.is_deleted === 1
  const createdAt = msg.created_at ? timeFormatter.format(new Date(msg.created_at)) : ''
  const url = mediaUrl(msg.file_url || msg.content)
  const isMedia = ['image','video','audio','voice','file'].includes(msg.type)

  const renderStatus = () => {
    if (!isOwn) return null
    const stats = Array.isArray(msg.status) ? msg.status : []
    if (stats.length === 0) {
      return <TickSingle color="#9ca3af" />
    }
    const allDelivered = stats.every(s => s.delivered_at)
    const allRead = stats.every(s => s.read_at)
    if (allRead) return <TickDouble color="#53bdeb" />
    if (allDelivered) return <TickDouble color="#9ca3af" />
    return <TickSingle color="#9ca3af" />
  }

  const saveEdit = () => {
    if (!editContent.trim()) return
    getSocket()?.emit('message:edit', { message_id: msg.id, channel_id: channelId, content: editContent })
    updateMessage(channelId, msg.id, { content: editContent, is_edited: 1 })
    setEditing(false)
  }
  const deleteMsg = () => {
    if (!confirm('Delete this message?')) return
    getSocket()?.emit('message:delete', { message_id: msg.id, channel_id: channelId })
    deleteMessage(channelId, msg.id)
  }
  const toggleReaction = (emoji) => {
    const rx = Array.isArray(msg.reactions) ? msg.reactions : []
    const has = rx.some(r => r.emoji === emoji && r.user_id === user?.id)
    updateReaction(channelId, msg.id, emoji, user?.id, has ? 'removed' : 'added')
    getSocket()?.emit('reaction:toggle', { message_id: msg.id, channel_id: channelId, emoji })
    // Keep picker open; only close on outside click
  }
  const groupedReactions = () => {
    const rx = Array.isArray(msg.reactions) ? msg.reactions : []
    if (!rx.length) return {}
    return rx.reduce((acc, r) => { acc[r.emoji] = acc[r.emoji] || []; acc[r.emoji].push(r.user_id); return acc }, {})
  }

  if (isDeleted) {
    return (
      <div className={`flex w-full mb-2 ${isOwn ? 'justify-end' : 'justify-start'}`}>
        <div className={`message-bubble ${isOwn ? 'message-sent' : 'message-received'} opacity-60`}>
          <div className="text-xs italic text-white/70">This message was deleted</div>
        </div>
      </div>
    )
  }

  const renderMedia = () => {
    if (msg.type === 'image') {
      return <img src={url} onClick={() => window.open(url, '_blank')} alt={msg.file_name || 'Image'} className="max-w-[280px] max-h-[340px] object-cover rounded-lg cursor-pointer hover:brightness-95" />
    }
    if (msg.type === 'video') {
      return <video src={url} controls className="max-w-[280px] rounded-lg" />
    }
    if (msg.type === 'audio' || msg.type === 'voice') {
      return <audio src={url} controls className="max-w-[240px] h-10" />
    }
    if (msg.type === 'file') {
      return (
        <a href={url} target="_blank" rel="noreferrer" download className="flex items-center gap-3 px-3 py-2 bg-black/20 rounded-lg border border-white/5 hover:bg-black/30 max-w-[260px]">
          <span className="w-9 h-9 rounded-lg bg-brand-500/15 flex items-center justify-center text-brand-500 flex-shrink-0">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
          </span>
          <span className="min-w-0">
            <span className="block text-sm text-white truncate">{msg.file_name || msg.content}</span>
            <span className="block text-[11px] text-white/50">{fmtSize(msg.file_size) || 'Open file'}</span>
          </span>
        </a>
      )
    }
    return null
  }

  // Footer that holds time + tick INSIDE the bubble (WhatsApp style)
  const footer = (
    <div className="flex items-center gap-1 ml-2 mt-0.5 self-end flex-shrink-0">
      <span className="text-[10.5px] text-white/55 leading-none">{createdAt}</span>
      {isOwn && <span className="inline-flex items-center -mr-0.5">{renderStatus()}</span>}
    </div>
  )

  return (
    <div className={`flex w-full mb-1 ${isOwn ? 'justify-end' : 'justify-start'} group animate-fade-in`}
      onMouseEnter={() => setShowActions(true)}
      onMouseLeave={() => setShowActions(false)}>
      <div className={`message-bubble relative ${isOwn ? 'message-sent' : 'message-received'}`}>
        {!isOwn && (<div className="text-[11px] font-bold text-brand-500 mb-1 leading-none">{msg.sender_name}</div>)}
        {editing ? (
          <div className="min-w-[200px]">
            <textarea value={editContent} onChange={e => setEditContent(e.target.value)} className="text-sm resize-none bg-black/20 border-none p-1 w-full text-white" rows={2} autoFocus />
            <div className="flex justify-end gap-2 mt-1">
              <button onClick={() => setEditing(false)} className="text-[10px] uppercase font-bold text-white/60">Cancel</button>
              <button onClick={saveEdit} className="text-[10px] uppercase font-bold text-brand-100">Save</button>
            </div>
          </div>
        ) : isMedia ? (
          // Media: render media, then a small footer below it
          <div>
            {renderMedia()}
            <div className="flex justify-end mt-1">{footer}</div>
          </div>
        ) : (
          // Text: footer sits inline on the right of the last text line
          <div className="flex items-end flex-wrap">
            <p className="text-[14.5px] text-gray-100 whitespace-pre-wrap break-words leading-relaxed">{msg.content}</p>
            {footer}
          </div>
        )}

        {Object.keys(groupedReactions()).length > 0 && (
          <div className={`flex flex-wrap gap-1 mt-1.5 ${isOwn ? 'justify-end' : 'justify-start'}`}>
            {Object.entries(groupedReactions()).map(([emoji, users]) => (
              <button key={emoji} onClick={() => toggleReaction(emoji)} className={`flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[11px] border transition-colors ${users.includes(user?.id) ? 'bg-brand-500/25 border-brand-500' : 'bg-black/30 border-white/10 hover:border-white/30'}`}>
                <span className="text-[13px] leading-none">{emoji}</span>
                {users.length > 1 && <span className="text-white/80 leading-none">{users.length}</span>}
              </button>
            ))}
          </div>
        )}
      </div>

      {(showActions || showPicker) && !editing && (
        <div className={`flex items-center gap-0.5 mx-1.5 relative self-center ${isOwn ? 'flex-row-reverse' : 'flex-row'}`}>
          {/* Slim react button (small, not big circle) */}
          <button onClick={() => setShowPicker(v => !v)} title="React" className={`h-6 px-1.5 inline-flex items-center justify-center rounded-full text-gray-400 hover:text-white hover:bg-white/10 ${showPicker ? 'bg-white/10 text-white' : ''}`}>
            <SmileIcon />
          </button>
          {isOwn && (<button onClick={() => setEditing(true)} title="Edit" className="h-6 px-1.5 inline-flex items-center justify-center rounded-full text-gray-500 hover:text-white hover:bg-white/10"><PencilIcon /></button>)}
          {isOwn && (<button onClick={deleteMsg} title="Delete" className="h-6 px-1.5 inline-flex items-center justify-center rounded-full text-gray-500 hover:text-red-400 hover:bg-white/10"><TrashIcon /></button>)}
          {showPicker && (
            <ReactionPicker alignRight={isOwn} onPick={toggleReaction} onClose={() => setShowPicker(false)} />
          )}
        </div>
      )}
    </div>
  )
}