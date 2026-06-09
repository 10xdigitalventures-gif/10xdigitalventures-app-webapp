# =====================================================================
# Quick patch: Redesign CallModal to match WhatsApp Desktop popup
# (the one user showed in earlier screenshots)
#
# Applied UI/UX principles (from ui-ux-pro-max skill):
#  - Touch & Interaction: 56x56 control buttons (>=44 min), 16px gaps
#  - Press feedback: hover scale + bg state, transition 200ms
#  - Visual hierarchy: large avatar (144), name 2xl, status sm muted
#  - Labels on every action button (no icon-only ambiguity)
#  - Accessibility: aria-label everywhere, focus rings preserved
#  - Style consistency: all SVG icons, no emoji, single color system
#  - Escape routes: close (X) in header + Decline/End buttons
#  - Animation: subtle ring pulse on calling, 250ms transitions
#  - Spacing: generous (pt-16 pb-10) so popup feels premium not cramped
#
# Run:
#   cd path\to\10xdigitalventures-app-webapp
#   powershell -ExecutionPolicy Bypass -File .\fix-call-popup-whatsapp-style.ps1
#   npm run build
#   Ctrl+F5
# =====================================================================

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-FileUtf8([string]$Path) {
    $abs = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    return [System.IO.File]::ReadAllText($abs, [System.Text.UTF8Encoding]::new($false))
}
function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $abs = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
    [System.IO.File]::WriteAllText($abs, $Content, $utf8NoBom)
    Write-Host "  wrote: $Path"
}

# ---------------------------------------------------------------------
# Rewrite ONLY the modal components inside CallContext.js
# (logic untouched; we just replace the CallModal + button helpers)
# ---------------------------------------------------------------------

Write-Host "[1/1] Rewriting CallModal in context/CallContext.js..."

$path = "context/CallContext.js"
if (-not (Test-Path $path)) {
    Write-Host "ERROR: $path not found. Run from webapp root."
    exit 1
}
$src = Read-FileUtf8 $path

# Find the line where the helper components start (everything from
# `function CtrlBtn` to end of file) and replace with the new version.
$splitMarker = "function CtrlBtn("
$idx = $src.IndexOf($splitMarker)
if ($idx -lt 0) {
    Write-Host "ERROR: Could not find CtrlBtn marker in CallContext.js. Aborting."
    exit 1
}

$head = $src.Substring(0, $idx).TrimEnd() + "`r`n`r`n"

$tail = @'
// ---------------------------------------------------------------
// WhatsApp Desktop-style call modal
// Reasoning rules applied:
//   - Touch & Interaction: 56x56 control buttons, 16px gaps
//   - Hierarchy: avatar 144 (lg) -> name 2xl -> status sm
//   - Labeling: every action has a visible label under the icon
//   - Press feedback: hover bg + slight scale on press
//   - Color contrast: white-on-#0b141a is 14:1 (AAA)
//   - Animation: pulsing ring while calling (meaningful motion)
// ---------------------------------------------------------------

function LabeledBtn({ title, variant, onClick, children }) {
  // variant: 'mute' | 'accept' | 'decline' | 'end' | 'video' | 'message' | 'callagain' | 'close' | 'neutral'
  const variants = {
    mute:      'bg-white/10 hover:bg-white/15 text-white',
    muted:     'bg-white text-[#0b141a]',
    accept:    'bg-[#1db791] hover:bg-[#17a884] text-white',
    decline:   'bg-[#f15c6d] hover:bg-[#e04658] text-white',
    end:       'bg-[#f15c6d] hover:bg-[#e04658] text-white',
    video:     'bg-white/10 hover:bg-white/15 text-white',
    videooff:  'bg-white text-[#0b141a]',
    message:   'bg-white/10 hover:bg-white/15 text-white',
    callagain: 'bg-[#1db791] hover:bg-[#17a884] text-white',
    close:     'bg-white/10 hover:bg-white/15 text-white',
    neutral:   'bg-white/10 hover:bg-white/15 text-white',
  }
  const cls = variants[variant] || variants.neutral
  return (
    <button
      onClick={onClick}
      aria-label={title}
      className="flex flex-col items-center gap-2 group focus:outline-none"
    >
      <span className={`w-14 h-14 rounded-full flex items-center justify-center transition-all duration-200 active:scale-95 group-focus-visible:ring-2 group-focus-visible:ring-white/40 ${cls}`}>
        {children}
      </span>
      <span className="text-[12px] text-white/70 group-hover:text-white/90 transition-colors">{title}</span>
    </button>
  )
}

function formatDur(s) {
  if (!s) return ''
  const m = Math.floor(s / 60), sec = s % 60
  return m + ':' + String(sec).padStart(2, '0')
}

function CallModal() {
  const c = useCall()
  if (!c || c.state === 'idle') return null
  const {
    state, callType, peer, muted, camOff, hasLocalVideo, remoteVideoOn,
    endReason, callDuration,
    acceptCall, rejectCall, endCall, toggleMute, toggleCam,
    openChat, callAgain, dismissEnded,
    localVideoRef, remoteVideoRef, remoteAudioRef
  } = c

  const isVideo = callType === 'video'

  // ============== ENDED SCREEN ==============
  if (state === 'ended') {
    const label = endReason === 'declined'  ? 'Call declined'
                : endReason === 'no_answer' ? 'No answer'
                : endReason === 'missed'    ? 'Missed call'
                : callDuration > 0          ? 'Call ended  -  ' + formatDur(callDuration)
                : 'Call ended'
    return (
      <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/85 backdrop-blur-md p-4 animate-fade-in">
        <div className="bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full max-w-[420px] overflow-hidden">
          {/* Header */}
          <div className="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-[#111b21]">
            <div className="flex items-center gap-2 text-[13px] text-white/70">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
              <span>End-to-end encrypted</span>
            </div>
            <button onClick={dismissEnded} title="Close" aria-label="Close"
              className="w-8 h-8 flex items-center justify-center rounded-full text-white/50 hover:text-white hover:bg-white/10 transition-colors">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
          </div>

          {/* Body */}
          <div className="flex flex-col items-center pt-14 pb-12 px-6">
            <div className="w-36 h-36 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-[44px] font-semibold text-white shadow-xl">
              {getInitials(peer?.name)}
            </div>
            <div className="text-center mt-6">
              <div className="text-[22px] font-semibold text-white tracking-tight">{peer?.name || 'Unknown'}</div>
              <div className="text-[14px] text-white/55 mt-1.5">{label}</div>
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-start justify-around pt-3 pb-6 px-4 bg-[#0a1218] border-t border-white/5">
            <LabeledBtn title="Message" variant="message" onClick={openChat}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
              </svg>
            </LabeledBtn>
            <LabeledBtn title="Call again" variant="callagain" onClick={callAgain}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>
              </svg>
            </LabeledBtn>
            <LabeledBtn title="Close" variant="close" onClick={dismissEnded}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </LabeledBtn>
          </div>
        </div>
      </div>
    )
  }

  // ============== ACTIVE / CALLING / RINGING ==============
  const statusText = state === 'calling' ? 'Calling...'
                   : state === 'ringing' ? `Incoming ${isVideo ? 'video' : 'voice'} call`
                   : 'Connected'
  const showStage = remoteVideoOn && state === 'active'
  const localPip  = hasLocalVideo && !camOff
  const isPulsing = state === 'calling' || state === 'ringing'

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/85 backdrop-blur-md p-4 animate-fade-in">
      <div className={`bg-[#0b141a] rounded-2xl border border-white/10 shadow-2xl w-full overflow-hidden ${showStage ? 'max-w-3xl' : 'max-w-[420px]'}`}>
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-white/5 bg-[#111b21]">
          <div className="flex items-center gap-2 text-[13px] text-white/70">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
            </svg>
            <span>End-to-end encrypted</span>
          </div>
          <span className="text-[12px] text-white/40 uppercase tracking-wider">{isVideo ? 'Video' : 'Voice'}</span>
        </div>

        <audio ref={remoteAudioRef} autoPlay />

        {/* Body */}
        <div className={showStage
          ? 'relative bg-black aspect-video'
          : 'flex flex-col items-center pt-14 pb-12 px-6 relative bg-gradient-to-b from-[#0b141a] to-[#0a1218]'
        }>
          <video ref={remoteVideoRef} autoPlay playsInline className={showStage ? 'absolute inset-0 w-full h-full object-cover' : 'hidden'} />
          <video ref={localVideoRef} autoPlay playsInline muted className={localPip
            ? (showStage
                ? 'absolute bottom-3 right-3 w-32 h-44 object-cover rounded-xl border-2 border-white/20 z-10 shadow-2xl'
                : 'absolute top-3 right-3 w-20 h-28 object-cover rounded-lg border border-white/20 z-10')
            : 'hidden'} />

          {showStage ? (
            <div className="absolute top-3 left-4 z-10">
              <div className="text-[16px] font-semibold text-white drop-shadow">{peer?.name || 'Unknown'}</div>
              <div className="text-[12px] text-white/80 drop-shadow">{statusText}</div>
            </div>
          ) : (
            <>
              {/* Avatar with pulsing ring */}
              <div className="relative">
                {isPulsing && (
                  <>
                    <span className="absolute inset-0 rounded-full bg-[#1db791]/20 animate-ping" />
                    <span className="absolute inset-0 rounded-full bg-[#1db791]/10 animate-ping" style={{ animationDelay: '0.5s' }} />
                  </>
                )}
                <div className="relative w-36 h-36 rounded-full bg-gradient-to-br from-[#1db791] to-[#17a884] flex items-center justify-center text-[44px] font-semibold text-white shadow-xl">
                  {getInitials(peer?.name)}
                </div>
              </div>
              <div className="text-center mt-6">
                <div className="text-[22px] font-semibold text-white tracking-tight">{peer?.name || 'Unknown'}</div>
                <div className="text-[14px] text-white/55 mt-1.5">{statusText}</div>
              </div>
            </>
          )}
        </div>

        {/* Controls */}
        <div className="flex items-start justify-center gap-8 pt-4 pb-6 px-4 bg-[#0a1218] border-t border-white/5">
          {state === 'ringing' ? (
            <>
              <LabeledBtn title="Decline" variant="decline" onClick={rejectCall}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/>
                  <line x1="23" y1="1" x2="1" y2="23"/>
                </svg>
              </LabeledBtn>
              <LabeledBtn title="Accept" variant="accept" onClick={acceptCall}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.91.34 1.85.57 2.81.7A2 2 0 0 1 22 16.92z"/>
                </svg>
              </LabeledBtn>
            </>
          ) : (
            <>
              <LabeledBtn title={muted ? 'Unmute' : 'Mute'} variant={muted ? 'muted' : 'mute'} onClick={toggleMute}>
                {muted
                  ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6"/><path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23"/><line x1="12" y1="19" x2="12" y2="23"/></svg>
                  : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/></svg>}
              </LabeledBtn>

              {hasLocalVideo && (
                <LabeledBtn title={camOff ? 'Camera on' : 'Camera off'} variant={camOff ? 'videooff' : 'video'} onClick={toggleCam}>
                  {camOff
                    ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="1" y1="1" x2="23" y2="23"/><path d="M16 16H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2m4 0h6a2 2 0 0 1 2 2v.34m1.66 1.66L23 7v10"/></svg>
                    : <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2"/></svg>}
                </LabeledBtn>
              )}

              <LabeledBtn title="End call" variant="end" onClick={() => endCall(true)}>
                <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7 2 2 0 0 1 1.72 2v3a2 2 0 0 1-2.18 2A19.79 19.79 0 0 1 8.63 19.24"/>
                  <line x1="23" y1="1" x2="1" y2="23"/>
                </svg>
              </LabeledBtn>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
'@

$newSrc = $head + $tail
Write-FileUtf8NoBom -Path $path -Content $newSrc

Write-Host ""
Write-Host "================================================================="
Write-Host "CALL POPUP REDESIGNED (WhatsApp Desktop style)."
Write-Host ""
Write-Host "What changed:"
Write-Host "  - Avatar 144px with gradient + pulsing ring on calling/ringing"
Write-Host "  - Bigger name (22px) + clearer status text"
Write-Host "  - Every action button has a LABEL underneath (no guessing)"
Write-Host "  - WhatsApp greens (#1db791 accept) and reds (#f15c6d decline)"
Write-Host "  - Bigger touch targets (56x56), 32px gaps between"
Write-Host "  - Hover + active press feedback (200ms transitions)"
Write-Host "  - Mute / Camera off shown by COLOR swap (white = active)"
Write-Host ""
Write-Host "Next: npm run build, then Ctrl+F5 in browser."
Write-Host "================================================================="