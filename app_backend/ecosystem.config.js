// PM2 process config for the EktaHR API — a FREE, open-source load balancer.
//
// `exec_mode: 'cluster'` makes PM2 spawn N copies of the API (one per CPU core
// by default) and round-robin every incoming request across them. So when many
// users log in / load screens at the same time, the work is spread over all
// cores instead of queuing on a single Node process.
//
// All cluster workers share the same PORT — PM2 + Node's cluster module handle
// the shared listening socket automatically; no nginx/HAProxy and no paid cloud
// load balancer required for single-machine balancing.
//
// Run:    pm2 start ecosystem.config.js
// Reload (zero-downtime): pm2 reload ektahr-api
// Logs:   pm2 logs ektahr-api
// Status: pm2 ls
//
// Override worker count without editing this file:
//   WEB_INSTANCES=2 pm2 start ecosystem.config.js   (e.g. leave a core free)

module.exports = {
  apps: [
    {
      name: 'ektahr-api',
      script: 'index.js',
      cwd: './',
      exec_mode: 'cluster',
      // 'max' = one worker per CPU core. This machine has 4 cores → 4 workers.
      instances: process.env.WEB_INSTANCES || 'max',
      env: { NODE_ENV: 'production' },
      // Restart a worker if it leaks past this; the others keep serving traffic.
      max_memory_restart: '600M',
      // Give in-flight requests time to finish on reload/stop.
      kill_timeout: 8000,
      autorestart: true,
    },
    {
      // Daily celebration-wish scheduler. This is a long-running scheduler that
      // must run as EXACTLY ONE process — never one per web worker — so it stays
      // in fork mode with a single instance.
      name: 'ektahr-cron',
      script: 'src/scripts/cronSendNotifications.js',
      cwd: './',
      exec_mode: 'fork',
      instances: 1,
      env: { NODE_ENV: 'production' },
      max_memory_restart: '256M',
      autorestart: true,
    },
  ],
};
