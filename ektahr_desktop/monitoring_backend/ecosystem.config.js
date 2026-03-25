module.exports = {
  apps: [
    {
<<<<<<< HEAD
      name: 'prod-monitoring-api',
=======
      name: 'monitoring-api',
>>>>>>> development
      script: 'index.js',
      cwd: './',
      instances: 1,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '500M'
    },
    {
<<<<<<< HEAD
      name: 'prod-monitoring-worker',
=======
      name: 'monitoring-worker',
>>>>>>> development
      script: 'worker.js',
      cwd: './',
      instances: 1,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '500M'
    },
    {
<<<<<<< HEAD
      name: 'prod-monitoring-attendance-cron',
=======
      name: 'monitoring-attendance-cron',
>>>>>>> development
      script: 'src/cron/attendanceCheckCron.js',
      cwd: './',
      instances: 1,
      exec_mode: 'fork',
      env: { NODE_ENV: 'production' },
      max_memory_restart: '256M'
    }
  ]
};
