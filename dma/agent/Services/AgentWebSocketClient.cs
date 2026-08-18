using System;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace EktaDMAAgent.Services
{
    public class AgentWebSocketClient : IDisposable
    {
        private readonly string _deviceId;
        private readonly string _serverWsUrl;
        private ClientWebSocket? _webSocket;
        private CancellationTokenSource? _cts;
        private Task? _receiveTask;
        private Task? _streamTask;
        private readonly DxgiScreenCapturer _capturer;
        private bool _isStreaming;
        private long _jpegQuality = 75L;
        private int _frameIntervalMs = 66; // ~15 FPS default

        public bool IsConnected => _webSocket != null && _webSocket.State == WebSocketState.Open;

        public AgentWebSocketClient(string deviceId, string serverWsUrl = "ws://localhost:9000")
        {
            _deviceId = deviceId;
            _serverWsUrl = serverWsUrl;
            _capturer = new DxgiScreenCapturer();
        }

        public async Task StartAsync()
        {
            _cts = new CancellationTokenSource();
            await ConnectToServerAsync(_cts.Token);
        }

        private async Task ConnectToServerAsync(CancellationToken token)
        {
            try
            {
                _webSocket = new ClientWebSocket();
                string hostname = Environment.MachineName;
                string username = Environment.UserName;

                Uri uri = new Uri($"{_serverWsUrl}/agent?deviceId={Uri.EscapeDataString(_deviceId)}&hostname={Uri.EscapeDataString(hostname)}&user={Uri.EscapeDataString(username)}");

                Console.WriteLine($"[EktaDMA Agent] Connecting to signaling server at {uri}...");
                await _webSocket.ConnectAsync(uri, token);
                Console.WriteLine($"[EktaDMA Agent] Connected successfully as device {_deviceId}");

                _receiveTask = Task.Run(() => ReceiveLoopAsync(_cts.Token), token);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[EktaDMA Agent] Connection failed: {ex.Message}");
            }
        }

        private async Task ReceiveLoopAsync(CancellationToken token)
        {
            var buffer = new byte[4096];
            while (!token.IsCancellationRequested && IsConnected)
            {
                try
                {
                    var result = await _webSocket!.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        StopStreaming();
                        break;
                    }

                    if (result.MessageType == WebSocketMessageType.Text)
                    {
                        string json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                        HandleControlMessage(json);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[EktaDMA Agent] Receive loop error: {ex.Message}");
                    break;
                }
            }
        }

        private void HandleControlMessage(string jsonText)
        {
            try
            {
                using (JsonDocument doc = JsonDocument.Parse(jsonText))
                {
                    JsonElement root = doc.RootElement;
                    if (root.TryGetProperty("type", out JsonElement typeProp))
                    {
                        string type = typeProp.GetString() ?? "";

                        if (type == "START_STREAM")
                        {
                            Console.WriteLine("[EktaDMA Agent] Received START_STREAM request from Admin");
                            StartStreaming();
                        }
                        else if (type == "STOP_STREAM")
                        {
                            Console.WriteLine("[EktaDMA Agent] Received STOP_STREAM request");
                            StopStreaming();
                        }
                        else if (type == "INPUT_EVENT")
                        {
                            HandleInputEvent(root);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[EktaDMA Agent] Message parsing error: {ex.Message}");
            }
        }

        private void HandleInputEvent(JsonElement root)
        {
            if (!root.TryGetProperty("eventType", out JsonElement evtTypeProp)) return;
            string evtType = evtTypeProp.GetString() ?? "";

            int x = root.TryGetProperty("x", out JsonElement xProp) ? xProp.GetInt32() : 0;
            int y = root.TryGetProperty("y", out JsonElement yProp) ? yProp.GetInt32() : 0;

            if (evtType == "MOUSE_MOVE")
            {
                InputInjector.InjectMouseMove(x, y);
            }
            else if (evtType == "MOUSE_CLICK")
            {
                string button = root.TryGetProperty("button", out JsonElement bProp) ? bProp.GetString() ?? "LEFT" : "LEFT";
                bool isDoubleClick = root.TryGetProperty("isDoubleClick", out JsonElement dcProp) && dcProp.GetBoolean();
                InputInjector.InjectMouseClick(x, y, button, isDoubleClick);
            }
            else if (evtType == "MOUSE_WHEEL")
            {
                int delta = root.TryGetProperty("delta", out JsonElement dProp) ? dProp.GetInt32() : 0;
                InputInjector.InjectMouseWheel(delta);
            }
            else if (evtType == "KEY_EVENT")
            {
                byte vk = root.TryGetProperty("vkCode", out JsonElement vkProp) ? (byte)vkProp.GetInt32() : (byte)0;
                bool isKeyDown = root.TryGetProperty("isKeyDown", out JsonElement kdProp) && kdProp.GetBoolean();
                InputInjector.InjectKeyEvent(vk, isKeyDown);
            }
        }

        private void StartStreaming()
        {
            if (_isStreaming) return;
            _isStreaming = true;
            SendResolutionInfo();
            _streamTask = Task.Run(() => StreamLoopAsync(_cts!.Token));
        }

        private void StopStreaming()
        {
            _isStreaming = false;
        }

        private async Task StreamLoopAsync(CancellationToken token)
        {
            Console.WriteLine("[EktaDMA Agent] Starting desktop screen frame capture stream...");
            while (_isStreaming && !token.IsCancellationRequested && IsConnected)
            {
                try
                {
                    byte[]? frameData = _capturer.CaptureScreenFrame(_jpegQuality);
                    if (frameData != null && frameData.Length > 0)
                    {
                        await _webSocket!.SendAsync(
                            new ArraySegment<byte>(frameData),
                            WebSocketMessageType.Binary,
                            true,
                            token
                        );
                    }

                    await Task.Delay(_frameIntervalMs, token);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[EktaDMA Agent] Stream loop error: {ex.Message}");
                    break;
                }
            }
            _isStreaming = false;
            Console.WriteLine("[EktaDMA Agent] Stopped desktop screen stream.");
        }

        private async void SendResolutionInfo()
        {
            if (!IsConnected) return;
            try
            {
                var bounds = _capturer.PrimaryScreenBounds;
                string payload = JsonSerializer.Serialize(new
                {
                    type = "RESOLUTION_INFO",
                    width = bounds.Width,
                    height = bounds.Height
                });
                byte[] bytes = Encoding.UTF8.GetBytes(payload);
                await _webSocket!.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch { }
        }

        public async Task SendHeartbeatAsync()
        {
            if (!IsConnected) return;
            try
            {
                string payload = JsonSerializer.Serialize(new
                {
                    type = "HEARTBEAT",
                    currentUser = Environment.UserName,
                    hostname = Environment.MachineName
                });
                byte[] bytes = Encoding.UTF8.GetBytes(payload);
                await _webSocket!.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch { }
        }

        public void Dispose()
        {
            _cts?.Cancel();
            _isStreaming = false;
            _webSocket?.Dispose();
            _capturer?.Dispose();
        }
    }
}
