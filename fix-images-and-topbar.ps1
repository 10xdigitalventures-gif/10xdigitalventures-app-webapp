# ============================================================================
#  10x Chat â€” fix chat images + redesign the conversation topbar
#   - Images: resolve relative /uploads paths against the API origin so they
#     load on the web domain (chat.* vs api.*).
#   - Topbar: clean WhatsApp-style header with SVG icons, presence/typing,
#     voice + video call buttons, and a members/info toggle.
#
#  Run from the repo root:
#      cd path\to\10xdigitalventures-app-webapp
#      powershell -ExecutionPolicy Bypass -File .\fix-images-and-topbar.ps1
# ============================================================================

$ErrorActionPreference = "Stop"
if (-not (Test-Path ".\package.json")) {
  Write-Host "ERROR: run this from the repo root (package.json not found)." -ForegroundColor Red
  exit 1
}

function Patch($Path, $Find, $Replace) {
  $full = Join-Path (Get-Location) $Path
  if (-not (Test-Path $full)) { Write-Host "  skip (not found): $Path" -ForegroundColor Yellow; return }
  $c = [System.IO.File]::ReadAllText($full)
  if ($c.Contains($Replace)) { Write-Host "  already patched: $Path" -ForegroundColor DarkGray; return }
  if (-not $c.Contains($Find)) { Write-Host "  pattern NOT found in $Path" -ForegroundColor Yellow; return }
  if (-not (Test-Path "$full.bak")) { Copy-Item $full "$full.bak" -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $c.Replace($Find, $Replace), $enc)
  Write-Host "  patched: $Path" -ForegroundColor Green
}

function AppendIfMissing($Path, $Marker, $Content) {
  $full = Join-Path (Get-Location) $Path
  if (-not (Test-Path $full)) { Write-Host "  skip (not found): $Path" -ForegroundColor Yellow; return }
  $c = [System.IO.File]::ReadAllText($full)
  if ($c.Contains($Marker)) { Write-Host "  already has mediaUrl: $Path" -ForegroundColor DarkGray; return }
  if (-not (Test-Path "$full.bak")) { Copy-Item $full "$full.bak" -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, ($c.TrimEnd() + "`r`n`r`n" + $Content + "`r`n"), $enc)
  Write-Host "  appended mediaUrl to $Path" -ForegroundColor Green
}

function Write-RepoFile($Path, $Content) {
  $full = Join-Path (Get-Location) $Path
  $dir  = Split-Path $full -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $full) -and -not (Test-Path "$full.bak")) { Copy-Item $full "$full.bak" -Force }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($full, $Content, $enc)
  Write-Host "  wrote $Path" -ForegroundColor Green
}

Write-Host "`n[1/3] Adding media URL resolver to lib/chatFormat.js..." -ForegroundColor Cyan
$mediaUrlFn = @'
// Resolve a stored file path/url to a loadable absolute URL.
// Files live on the API origin (e.g. https://api.10xdigitalventures.com),
// while the web app runs on a different origin, so relative paths must be
// prefixed. Handles full URLs, "/uploads/x.jpg" paths, and bare filenames.
export function mediaUrl(u) {
  if (!u) return ''
  const s = String(u)
  if (/^(https?:|data:|blob:)/i.test(s)) return s
  let base = process.env.NEXT_PUBLIC_SOCKET_URL || ''
  if (!base) base = (process.env.NEXT_PUBLIC_API_URL || '').replace(/\/api\/?$/, '')
  base = base.replace(/\/$/, '')
  if (s.startsWith('/')) return base + s
  return base + '/uploads/' + s
}
'@
AppendIfMissing "lib\chatFormat.js" 'export function mediaUrl' $mediaUrlFn

Write-Host "`n[2/3] Fixing image/file rendering in components/Message.js..." -ForegroundColor Cyan

# add the import next to the socket import
$impFind = @'
import { getSocket } from '@/lib/socket'
'@
$impRepl = @'
import { getSocket } from '@/lib/socket'
import { mediaUrl } from '@/lib/chatFormat'
'@
Patch "components\Message.js" $impFind $impRepl

# image: resolve src + open full image on click
$imgFind = @'
src={msg.file_url || msg.content} alt="Image"
'@
$imgRepl = @'
src={mediaUrl(msg.file_url || msg.content)} onClick={() => window.open(mediaUrl(msg.file_url || msg.content), '_blank')} alt="Image"
'@
Patch "components\Message.js" $imgFind $imgRepl

# file download link: resolve href
Patch "components\Message.js" 'href={msg.file_url}' 'href={mediaUrl(msg.file_url)}'

Write-Host "`n[3/3] Rewriting the conversation topbar (app/chat/[channelId]/page.js)..." -ForegroundColor Cyan
$channelPage = @'
'use client'
import { useEffect, useRef, useState } from 'react'
import { useParams } from 'next/navigation'
import toast from 'react-hot-toast'
import useChatStore from '@/store/chatStore'
import api from '@/lib/api'
import Message from '@/components/Message'
import MessageInput from '@/components/MessageInput'
import MembersList from '@/components/MembersList'
import { getSocket } from '@/lib/socket'

const ICO = { width: 20, height: 20, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true }
function HashIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="4" y1="9" x2="20" y2="9"/><line x1="4" y1="15" x2="20" y2="15"/><line x1="10" y1="3" x2="8" y2="21"/><line x1="16" y1="3" x2="14" y2="21"/></svg>) }
function UserIcon() { return (<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>) }
function PhoneIcon() { return (<svg {...ICO}><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/></svg>) }
function VideoIcon() { return (<svg {...ICO}><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>) }
function SearchIcon() { return (<svg {...ICO}><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>) }
function InfoIcon() { return (<svg {...ICO}><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>) }

function IconBtn({ title, onClick, children }) {
  return (<button onClick={onClick} title={title} aria-label={title} className="w-9 h-9 flex items-center justify-center rounded-full text-gray-400 hover:bg-white/5 hover:text-white transition-colors">{children}</button>)
}

export default function ChannelPage() {
  const { channelId } = useParams()
  const { channels, messages, members, setMessages, setMembers, setActiveChannel, typingUsers, user } = useChatStore()
  const [loading, setLoading] = useState(true)
  const [showMembers, setShowMembers] = useState(true)
  const bottomRef = useRef(null)
  const scrollRef = useRef(null)

  const channel = channels.find(c => c.id === channelId)
  const isDM = channel?.type === 'dm'
  const channelMessages = messages[channelId] || []

  const typingInChannel = typingUsers[channelId]
    ? [...typingUsers[channelId]].filter(id => id !== user?.id)
    : []

  useEffect(() => {
    if (!channelId) return
    setActiveChannel(channel)
    setLoading(true)
    Promise.all([
      api.get(`/messages/${channelId}`),
      api.get(`/channels/${channelId}/members`),
    ]).then(([msgRes, memRes]) => {
      const list = Array.isArray(msgRes.data?.data) ? msgRes.data.data : (Array.isArray(msgRes.data) ? msgRes.data : [])
      const mem = Array.isArray(memRes.data?.data) ? memRes.data.data : (Array.isArray(memRes.data) ? memRes.data : [])
      setMessages(channelId, list)
      setMembers(mem)
      setLoading(false)
      const unreadIds = list
        .filter(m => m.sender_id !== user?.id && (!Array.isArray(m.status) || !m.status.some(s => s.user_id === user?.id && s.read_at)))
        .map(m => m.id)
      if (unreadIds.length > 0) {
        getSocket()?.emit('message:read', { channel_id: channelId, message_ids: unreadIds })
      }
    }).catch(() => setLoading(false))
  }, [channelId, user?.id])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'auto' })
  }, [channelMessages.length])

  useEffect(() => {
    const socket = getSocket()
    if (!socket) return
    const handleNewMessage = (msg) => {
      if (msg.channel_id === channelId && msg.sender_id !== user?.id) {
        socket.emit('message:read', { channel_id: channelId, message_ids: [msg.id] })
      }
    }
    socket.on('message:new', handleNewMessage)
    return () => socket.off('message:new', handleNewMessage)
  }, [channelId, user?.id])

  const handleCall = (type) => {
    toast(`${type === 'video' ? 'Video' : 'Voice'} calling is being set up - coming soon`)
  }

  const subtitle = typingInChannel.length > 0
    ? 'typing...'
    : isDM ? 'online' : `${members?.length || 0} members`

  return (
    <div className="flex flex-1 overflow-hidden">
      <div className="flex flex-col flex-1 overflow-hidden relative">
        {/* Topbar */}
        <div className="flex items-center justify-between px-4 py-2 border-b border-[#2a2d35] bg-[#111820] flex-shrink-0 z-10">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-10 h-10 rounded-full bg-[#2a3942] flex items-center justify-center text-brand-500 flex-shrink-0">
              {isDM ? <UserIcon /> : <HashIcon />}
            </div>
            <div className="min-w-0">
              <h2 className="font-semibold text-[15px] text-white truncate leading-tight">{channel?.name || 'loading...'}</h2>
              <p className={`text-[12px] truncate leading-tight ${typingInChannel.length > 0 ? 'text-brand-500' : 'text-gray-500'}`}>{subtitle}</p>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <IconBtn title="Voice call" onClick={() => handleCall('audio')}><PhoneIcon /></IconBtn>
            <IconBtn title="Video call" onClick={() => handleCall('video')}><VideoIcon /></IconBtn>
            <IconBtn title="Search"><SearchIcon /></IconBtn>
            <IconBtn title="Info & members" onClick={() => setShowMembers(v => !v)}><InfoIcon /></IconBtn>
          </div>
        </div>

        {/* Messages */}
        <div ref={scrollRef} className="flex-1 overflow-y-auto bg-[#0b0d11] scroll-smooth" style={{ backgroundImage: 'radial-gradient(circle, #1a1d24 0.5px, transparent 0.5px)', backgroundSize: '24px 24px' }}>
          <div className="chat-area">
            {loading ? (
              <div className="flex flex-col items-center justify-center h-full gap-4">
                <div className="w-8 h-8 border-2 border-brand-500 border-t-transparent rounded-full animate-spin" />
                <p className="text-sm text-gray-500 animate-pulse">Loading conversation...</p>
              </div>
            ) : channelMessages.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-center px-12">
                <div className="w-20 h-20 rounded-full bg-brand-500/5 flex items-center justify-center mb-6 text-brand-500">
                  {isDM ? <UserIcon /> : <HashIcon />}
                </div>
                <h3 className="text-xl font-bold text-white mb-2">{isDM ? channel?.name : `#${channel?.name || ''}`}</h3>
                <p className="text-gray-400 text-sm max-w-xs">Start the conversation by sending a message below.</p>
              </div>
            ) : (
              <>
                <div className="flex justify-center my-6">
                  <span className="px-3 py-1 rounded bg-[#1e2229] text-[11px] font-medium text-gray-500 uppercase tracking-wider">Messages are end-to-end encrypted</span>
                </div>
                {channelMessages.map(msg => (
                  <Message key={msg.id} msg={msg} channelId={channelId} />
                ))}
              </>
            )}
            <div ref={bottomRef} className="h-4" />
          </div>
        </div>

        {/* Input */}
        <div className="bg-[#12141a] p-1">
          <MessageInput channelId={channelId} />
        </div>
      </div>

      {showMembers && <MembersList />}
    </div>
  )
}
'@
Write-RepoFile "app\chat\[channelId]\page.js" $channelPage

Write-Host "`nDone." -ForegroundColor Cyan
$doGit = Read-Host "Commit and push? (y/n)"
if ($doGit -eq 'y') {
  git add "lib/chatFormat.js" "components/Message.js" "app/chat/[channelId]/page.js"
  git commit -m "fix(web): resolve media URLs for chat images; redesign conversation topbar (SVG icons, call buttons, members toggle)"
  $push = Read-Host "Push now? (y/n)"
  if ($push -eq 'y') { git push; Write-Host "`nPushed. Rebuild/redeploy to see it live." -ForegroundColor Green }
  else { Write-Host "`nCommitted locally. Push later with: git push" -ForegroundColor Yellow }
} else {
  Write-Host "`nSkipped git. Review with: git diff" -ForegroundColor Yellow
}
Write-Host "`nIMPORTANT for images: your web env must have NEXT_PUBLIC_SOCKET_URL set to the API origin," -ForegroundColor Yellow
Write-Host "e.g. NEXT_PUBLIC_SOCKET_URL=https://api.10xdigitalventures.com  (sockets already use it, so it's likely set)." -ForegroundColor Yellow
Write-Host "Test locally: npm run dev -> open a chat." -ForegroundColor Cyan