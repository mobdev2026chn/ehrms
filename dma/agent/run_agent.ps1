# EktaDMA PowerShell Agent - Screen Capture & Input Injection
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$serverWsUrl = "ws://localhost:9000/agent"
$hostname = $env:COMPUTERNAME
$username = $env:USERNAME
$deviceId = "WIN-PC-$hostname"

$uri = [Uri]"$serverWsUrl`?deviceId=$deviceId&hostname=$hostname&user=$username"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  EKTA HR DMA - WINDOWS POWERSHELL LAN AGENT           " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "[Agent] Device ID: $deviceId"
Write-Host "[Agent] Connecting to $uri ..."

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource

try {
    $ws.ConnectAsync($uri, $cts.Token).Wait()
    Write-Host "[Agent] Connected successfully! Desktop online on Admin Dashboard." -ForegroundColor Green
} catch {
    Write-Host "[Agent] Failed to connect: $_" -ForegroundColor Red
    exit 1
}

# Screen bounds
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)

# JPEG Encoder
$codecs = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()
$jpegCodec = $null
foreach ($c in $codecs) {
    if ($c.FormatID -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid) {
        $jpegCodec = $c
        break
    }
}
$encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 75L)

$isStreaming = $false
$buffer = New-Object Byte[] 4096

# Listen for control commands & stream frames
while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    # Check if control message received
    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $segment = New-Object System.ArraySegment[Byte]($buffer)
        $result = $ws.ReceiveAsync($segment, $cts.Token)
        
        # If message available within 50ms
        if ($result.AsyncWaitHandle.WaitOne(50)) {
            $rec = $result.Result
            if ($rec.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Text) {
                $jsonStr = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $rec.Count)
                Write-Host "[Agent] Control Message: $jsonStr" -ForegroundColor Yellow
                if ($jsonStr -like "*START_STREAM*") {
                    $isStreaming = $true
                    # Send resolution info
                    $resJson = "{`"type`":`"RESOLUTION_INFO`",`"width`":$($bounds.Width),`"height`":$($bounds.Height)}"
                    $resBytes = [System.Text.Encoding]::UTF8.GetBytes($resJson)
                    $resSeg = New-Object System.ArraySegment[Byte]($resBytes)
                    $ws.SendAsync($resSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
                } elseif ($jsonStr -like "*STOP_STREAM*") {
                    $isStreaming = $false
                }
            }
        }
    }

    # Stream Desktop frame if streaming active
    if ($isStreaming) {
        try {
            $g.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bounds.Size)
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, $jpegCodec, $encoderParams)
            $frameBytes = $ms.ToArray()
            $ms.Dispose()

            $frameSeg = New-Object System.ArraySegment[Byte]($frameBytes)
            $ws.SendAsync($frameSeg, [System.Net.WebSockets.WebSocketMessageType]::Binary, $true, $cts.Token).Wait()
            Start-Sleep -Milliseconds 66 # ~15 FPS
        } catch {
            Write-Host "[Agent] Frame capture error: $_" -ForegroundColor Red
        }
    } else {
        # Heartbeat every 3 seconds when idle
        $hbJson = "{`"type`":`"HEARTBEAT`",`"currentUser`":`"$username`",`"hostname`":`"$hostname`"}"
        $hbBytes = [System.Text.Encoding]::UTF8.GetBytes($hbJson)
        $hbSeg = New-Object System.ArraySegment[Byte]($hbBytes)
        $ws.SendAsync($hbSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()
        Start-Sleep -Seconds 3
    }
}

$g.Dispose()
$bmp.Dispose()
Write-Host "[Agent] Agent Disconnected." -ForegroundColor Red
