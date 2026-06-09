# =====================================================================
# Quick fix: "Calls are available in direct messages" toast on groups
#
# Problem: handleCall() in app/chat/[channelId]/page.js still blocks
# non-DM channels with a toast. We need it to:
#   - DM        -> use useCall().startCall(peer.id, peer.name, type)
#   - Group/CH  -> use useGroupCall().startCall(channelId, type)
#
# Also ensures:
#   - useGroupCall is imported
#   - GroupCallProvider wraps the chat layout (in case earlier script
#     missed it)
#
# Run:
#   cd path\to\10xdigitalventures-app-webapp
#   powershell -ExecutionPolicy Bypass -File .\fix-groupcall-button.ps1
#   npm run build   (or restart dev)
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
# 1) Verify GroupCallContext file exists; if not, abort with hint.
# ---------------------------------------------------------------------
if (-not (Test-Path "context/GroupCallContext.js")) {
    Write-Host ""
    Write-Host "ERROR: context/GroupCallContext.js not found."
    Write-Host "Run fix-encoding-scroll-groupcall-webapp.ps1 first to create it."
    exit 1
}

# ---------------------------------------------------------------------
# 2) Patch app/chat/[channelId]/page.js
# ---------------------------------------------------------------------
Write-Host "[1/2] Patching app/chat/[channelId]/page.js -- smart handleCall..."

$pagePath = "app/chat/[channelId]/page.js"
$page = Read-FileUtf8 $pagePath

# 2a) Import useGroupCall (idempotent)
if ($page -notmatch "useGroupCall") {
    $page = $page -replace "import \{ useCall \} from '@/context/CallContext'",
                           "import { useCall } from '@/context/CallContext'`r`nimport { useGroupCall } from '@/context/GroupCallContext'"
    Write-Host "  + imported useGroupCall"
}

# 2b) Replace handleCall with smart router
$oldHandle = @"
  const handleCall = (type) => {
    if (!isDM || !dmPeer) { toast('Calls are available in direct messages'); return }
    if (!call?.startCall) { toast('Calling is not ready'); return }
    call.startCall(dmPeer.id, dmPeer.name, type)
  }
"@
$newHandle = @"
  const groupCall = useGroupCall()
  const handleCall = (type) => {
    if (isDM) {
      if (!dmPeer) { toast('No peer to call'); return }
      if (!call?.startCall) { toast('Calling is not ready'); return }
      call.startCall(dmPeer.id, dmPeer.name, type)
    } else {
      if (!groupCall?.startCall) { toast('Group calling is not ready'); return }
      groupCall.startCall(channelId, type)
    }
  }
"@
if ($page.Contains($oldHandle.Trim())) {
    $page = $page.Replace($oldHandle.Trim(), $newHandle.Trim())
    Write-Host "  + handleCall is now group-aware"
} elseif ($page -match "groupCall\?\.startCall") {
    Write-Host "  = handleCall already group-aware (skipped)"
} else {
    Write-Host "  ! handleCall block not in expected shape -- manual check needed"
}

Write-FileUtf8NoBom -Path $pagePath -Content $page

# ---------------------------------------------------------------------
# 3) Patch app/chat/layout.js -- ensure GroupCallProvider wraps children
# ---------------------------------------------------------------------
Write-Host "[2/2] Ensuring GroupCallProvider in app/chat/layout.js..."

$layPath = "app/chat/layout.js"
$lay = Read-FileUtf8 $layPath

if ($lay -notmatch "GroupCallProvider") {
    $lay = $lay -replace "import \{ CallProvider \} from '@/context/CallContext'",
                          "import { CallProvider } from '@/context/CallContext'`r`nimport { GroupCallProvider } from '@/context/GroupCallContext'"
    $lay = $lay.Replace("<CallProvider>",  "<CallProvider>`r`n      <GroupCallProvider>")
    $lay = $lay.Replace("</CallProvider>", "      </GroupCallProvider>`r`n    </CallProvider>")
    Write-Host "  + GroupCallProvider wrapped"
} else {
    Write-Host "  = GroupCallProvider already wrapped (skipped)"
}

Write-FileUtf8NoBom -Path $layPath -Content $lay

Write-Host ""
Write-Host "================================================================="
Write-Host "DONE. Next:"
Write-Host "  npm run build   (or dev server auto-reloads)"
Write-Host "  Ctrl+F5 in browser"
Write-Host ""
Write-Host "Test: open a GROUP/CHANNEL chat -> click voice/video icon"
Write-Host "      -> WhatsApp-style group call popup should appear."
Write-Host "================================================================="
