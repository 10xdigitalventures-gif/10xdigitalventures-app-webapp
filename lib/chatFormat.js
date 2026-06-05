// Chat-list formatting helpers (WhatsApp-style). Pure JS, no external deps.

export function formatChatTime(value) {
  if (!value) return ''
  const d = new Date(value)
  if (isNaN(d.getTime())) return ''
  const now = new Date()
  if (d.toDateString() === now.toDateString()) {
    let h = d.getHours()
    const m = d.getMinutes().toString().padStart(2, '0')
    const ap = h < 12 ? 'am' : 'pm'
    h = h % 12 || 12
    return `${h}:${m} ${ap}`
  }
  const yest = new Date(now)
  yest.setDate(now.getDate() - 1)
  if (d.toDateString() === yest.toDateString()) return 'Yesterday'
  const diffDays = (now.getTime() - d.getTime()) / 86400000
  if (diffDays < 7) return d.toLocaleDateString(undefined, { weekday: 'short' })
  return d.toLocaleDateString(undefined, { day: '2-digit', month: '2-digit', year: '2-digit' })
}

export function getInitials(name = '') {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return 'U'
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
}

const AVATAR_COLORS = ['#2a3942', '#3a2f5c', '#1f3d5c', '#5c4a1f', '#14564a', '#5c2f3a', '#2f5c3a', '#3a3a5c']
export function avatarColor(name = '') {
  let hash = 0
  const s = String(name || '')
  for (let i = 0; i < s.length; i++) hash = (hash * 31 + s.charCodeAt(i)) >>> 0
  return AVATAR_COLORS[hash % AVATAR_COLORS.length]
}

export function lastMsgTime(channel) {
  return channel?.last_message_at || channel?.last_message?.created_at || channel?.created_at || null
}

export function sortChannels(channels) {
  const arr = Array.isArray(channels) ? [...channels] : []
  return arr.sort((a, b) => {
    const pa = a?.is_pinned ? 1 : 0
    const pb = b?.is_pinned ? 1 : 0
    if (pa !== pb) return pb - pa
    const ta = new Date(lastMsgTime(a) || 0).getTime()
    const tb = new Date(lastMsgTime(b) || 0).getTime()
    return tb - ta
  })
}

// Returns { sender, kind, text } for the chat-list preview line.
export function previewOf(channel, currentUserId) {
  const lm = channel?.last_message
  if (!lm) return { sender: null, kind: 'text', text: channel?.topic || '' }
  const isGroup = channel?.type !== 'dm'
  let sender = null
  if (lm.sender_id && currentUserId && lm.sender_id === currentUserId) sender = 'You'
  else if (isGroup) sender = lm.sender_name || null
  const type = lm.type || 'text'
  if (type === 'image') return { sender, kind: 'image', text: 'Photo' }
  if (type === 'video') return { sender, kind: 'video', text: 'Video' }
  if (type === 'voice' || type === 'audio') return { sender, kind: 'voice', text: 'Voice message' }
  if (type === 'file') return { sender, kind: 'file', text: lm.content || 'Document' }
  return { sender, kind: 'text', text: lm.content || '' }
}

// 'read' | 'delivered' | 'sent' | null  (only when last message is from current user)
export function lastMsgStatus(channel, currentUserId) {
  const lm = channel?.last_message
  if (!lm || !currentUserId || lm.sender_id !== currentUserId) return null
  const stats = Array.isArray(lm.status) ? lm.status : null
  if (stats && stats.length > 0) {
    if (stats.every(s => s.read_at)) return 'read'
    if (stats.every(s => s.delivered_at)) return 'delivered'
    return 'sent'
  }
  if (lm.read_at || lm.is_read) return 'read'
  if (lm.delivered_at || lm.is_delivered) return 'delivered'
  return 'sent'
}

export function peerId(channel) {
  return channel?.peer_id || channel?.other_user_id || channel?.dm_user_id || null
}