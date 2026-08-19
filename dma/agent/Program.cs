using System;
using System.Threading.Tasks;
using EktaDMAAgent.Services;

namespace EktaDMAAgent
{
    internal class Program
    {
        static async Task Main(string[] args)
        {
            Console.WriteLine("=======================================================");
            Console.WriteLine("    EKTA HR - DMA (DESKTOP MONITORING & ACCESS AGENT)  ");
            Console.WriteLine("=======================================================");

            string deviceId = $"EHR-{Environment.MachineName.ToUpper()}";
            string serverWsUrl = "wss://track.ektahr.com:2005";

            Console.WriteLine($"[Agent] Device ID:      {deviceId}");
            Console.WriteLine($"[Agent] Hostname:       {Environment.MachineName}");
            Console.WriteLine($"[Agent] Logged User:    {Environment.UserName}");
            Console.WriteLine($"[Agent] Target Server:  {serverWsUrl}");

            using (var client = new AgentWebSocketClient(deviceId, serverWsUrl))
            {
                await client.StartAsync();

                // Heartbeat loop every 10 seconds
                while (true)
                {
                    await Task.Delay(10000);
                    if (client.IsConnected)
                    {
                        await client.SendHeartbeatAsync();
                    }
                    else
                    {
                        Console.WriteLine("[Agent] Connection offline. Retrying...");
                        await client.StartAsync();
                    }
                }
            }
        }
    }
}
