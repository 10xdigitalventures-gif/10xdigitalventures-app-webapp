'use client'
import { useState } from 'react'
import useChatStore from '@/store/chatStore'
import { getSocket } from '@/lib/socket'
import { mediaUrl } from '@/lib/chatFormat'

const EMOJIS = ['ðŸ‘','â¤ï¸','ðŸ˜‚','ðŸ˜®','ðŸ˜¢','ðŸ”¥','âœ…','ðŸ‘€']
const timeFormatter = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })

function fmtSize(bytes) {
  if (!bytes) return ''
  const kb = bytes / 1024
  return kb < 1024 ? `${Math.round(kb)} KB` : `${(kb / 1024).toFixed(1)} MB`
}

export default function Message({ msg, channelId }) {
  const { user, updateMessage, deleteMessage } = useChatStore()
  const [showActions, setShowActions] = useState(false)
  const [editing, setEditing] = useState(false)
  const [editContent, setEditContent] = useState(msg.content)
  const [showEmoji, setShowEmoji] = useState(false)

  const isOwn = msg.sender_id === user?.id
  const isDeleted = msg.is_deleted === 1
  const createdAt = msg.created_at ? timeFormatter.format(new Date(msg.created_at)) : ''
  const url = mediaUrl(msg.file_url || msg.content)

  const renderStatus = () => {
    if (!isOwn) return null
    const stats = Array.isArray(msg.status) ? msg.status : []
    const read = stats.length > 0 && stats.every(s => s.read_at)
    const delivered = stats.length > 0 && stats.every(s => s.delivered_at)
    if (read) return <span className="text-[#34b7f1]" title="Read">âœ“âœ“</span>
    if (delivered) return <span className="text-gray-400" title="Delivered">âœ“âœ“</span>
    return <span className="text-gray-400" title="Sent">âœ“</span>
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
    getSocket()?.emit('reaction:toggle', { message_id: msg.id, channel_id: channelId, emoji })
    setShowEmoji(false)
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
      return <img src={url} onClick={() => window.open(url, '_blank')} alt={msg.file_name || 'Image'} className="max-w-[280px] max-h-[340px] object-cover rounded-lg mb-1 cursor-pointer hover:brightness-95" />
    }
    if (msg.type === 'video') {
      return <video src={url} controls className="max-w-[280px] rounded-lg mb-1" />
    }
    if (msg.type === 'audio' || msg.type === 'voice') {
      return <audio src={url} controls className="mb-1 max-w-[240px] h-10" />
    }
    if (msg.type === 'file') {
      return (
        <a href={url} target="_blank" rel="noreferrer" download className="flex items-center gap-3 mb-1 px-3 py-2 bg-black/20 rounded-lg border border-white/5 hover:bg-black/30 max-w-[260px]">
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
    return <p className="text-[14.5px] text-gray-100 whitespace-pre-wrap break-words leading-relaxed mr-12">{msg.content}</p>
  }

  return (
    <div className={`flex w-full mb-1 ${isOwn ? 'justify-end' : 'justify-start'} group animate-fade-in`}
      onMouseEnter={() => setShowActions(true)} onMouseLeave={() => { setShowActions(false); setShowEmoji(false) }}>
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
        ) : (
          <div className="relative">
            {renderMedia()}
            <div className="flex items-center gap-1 absolute bottom-[-4px] right-[-4px] select-none">
              <span className="text-[10px] text-white/50 uppercase">{createdAt}</span>
              {renderStatus()}
            </div>
          </div>
        )}
        {Object.keys(groupedReactions()).length > 0 && (
          <div className="flex flex-wrap gap-1 mt-2 -mb-1">
            {Object.entries(groupedReactions()).map(([emoji, users]) => (
              <button key={emoji} onClick={() => toggleReaction(emoji)} className={`flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[10px] border transition-colors ${users.includes(user?.id) ? 'bg-brand-500/20 border-brand-500' : 'bg-black/10 border-white/5 hover:border-white/20'}`}>
                {emoji} <span>{users.length}</span>
              </button>
            ))}
          </div>
        )}
      </div>

      {showActions && !editing && (
        <div className={`flex items-center gap-1 mx-2 ${isOwn ? 'flex-row-reverse' : 'flex-row'}`}>
          <button onClick={() => setShowEmoji(!showEmoji)} className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-sm">ðŸ˜Š</button>
          {isOwn && (<button onClick={() => setEditing(true)} className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-xs text-gray-500 hover:text-white">âœï¸</button>)}
          {isOwn && (<button onClick={deleteMsg} className="w-7 h-7 flex items-center justify-center hover:bg-white/5 rounded-full text-xs text-gray-500 hover:text-red-400">ðŸ—‘ï¸</button>)}
          {showEmoji && (
            <div className={`absolute bottom-full mb-2 bg-[#1a1d24] border border-[#3a3d45] rounded-full p-1.5 flex gap-1 shadow-xl z-50 animate-fade-in ${isOwn ? 'right-0' : 'left-0'}`}>
              {EMOJIS.map(e => (<button key={e} onClick={() => toggleReaction(e)} className="w-8 h-8 flex items-center justify-center hover:scale-125 transition-transform text-lg">{e}</button>))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}