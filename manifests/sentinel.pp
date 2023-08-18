# == Defined Type: redis::sentinel
# Function to configure an redis sentinel server.
#
# === Parameters
#
# [*sentinel_name*]
#   Name of Sentinel instance. Default: call name of the function.
# [*sentinel_ip*]
#   Listen IP.
# [*sentinel_port*]
#   Listen port of Redis. Default: 26379
# [*sentinel_log_dir*]
#   Path for log. Full log path is <sentinel_log_dir>/redis-sentinel_<redis_name>.log. Default: /var/log
# [*sentinel_pid_dir*]
#   Path for pid file. Full pid path is <sentinel_pid_dir>/redis-sentinel_<redis_name>.pid. Default: /var/run
# [*requirepass*]
#   Configure Sentinel itself to require a password. By doing so, Sentinel will try to authenticate with the
#   same password to all the other Sentinels, so Sentinels in a given group need to be configured with the same
#   "requirepass" password. Check the following documentation for more info: https://redis.io/topics/sentinel
# [*monitors*]
#   Default is
#
# [*protected_mode*]
#   If no password and/or no bind address is set, sentinel defaults to being reachable only
#   on the loopback interface. Turn this behaviour off by setting protected mode to 'no'.
#
# {
#   'mymaster' => {
#     master_host             => '127.0.0.1',
#     master_port             => 6379,
#     quorum                  => 2,
#     down_after_milliseconds => 30000,
#     parallel-syncs          => 1,
#     failover_timeout        => 180000,
#     ## optional
#     auth-pass => 'secret_Password',
#     notification-script => '/var/redis/notify.sh',
#     client-reconfig-script => '/var/redis/reconfig.sh'
#   },
# }
#   All information for one or more sentinel monitors in a Hashmap.
# [*running*]
#   Configure if Sentinel should be running or not. Default: true
# [*enabled*]
#   Configure if Sentinel is started at boot. Default: true
# [*sentinel_run_dir*]
#
#   Default: `/var/run/redis`
#
#   Since sentinels automatically rewrite their config since version 2.8 the puppet managed config will be copied
#   to this directory and than sentinel will start with this copy.
# [*manage_logrotate*]
#   Configure logrotate rules for redis sentinel. Default: true
# [*sentinel_id*]
#   Configure the Sentinel ID.  (If defined, needs to be a 40 char string).  Default: undef
# [*announce_ip*]
#   Configure announce-ip in Sentinel configuration.  When announce-ip is provided,
#   the Sentinel will claim the specified IP address in HELLO messages used to gossip its presence,
#   instead of auto-detecting the local address as it usually does.
# [*announce_port*]
#   Configure announce-port in Sentinel configuration.  Similarly when announce-port is provided,
#   and is valid and non-zero, Sentinel will announce the specified TCP port.
define redis::sentinel (
  $ensure             = 'present',
  $sentinel_name      = $name,
  $sentinel_ip        = undef,
  $sentinel_port      = 26379,
  Stdlib::Absolutepath $sentinel_log_dir = '/var/log',
  Stdlib::Absolutepath $sentinel_pid_dir = '/var/run',
  Stdlib::Absolutepath $sentinel_run_dir = '/var/run/redis',
  Optional[Enum['yes', 'no']] $protected_mode = undef,
  $requirepass        = undef,
  $sentinel_auth_user = undef,
  $sentinel_auth_pass = undef,
  $sentinel_acl_users = [],
  Hash $monitors           = {
    'mymaster' => {
      master_host             => '127.0.0.1',
      master_port             => 6379,
      quorum                  => 2,
      down_after_milliseconds => 30000,
      parallel-syncs          => 1,
      failover_timeout        => 180000,
      # optional
      # auth-pass => 'secret_Password',
      # notification-script => '/var/redis/notify.sh',
      # client-reconfig-script => '/var/redis/reconfig.sh',
    },
  },
  Boolean $running = true,
  Boolean $enabled = true,
  Boolean $manage_logrotate = true,
  $announce_ip        = undef,
  $announce_port      = undef,
  $sentinel_id        = undef,
) {
  $sentinel_user              = $::redis::install::redis_user
  $sentinel_group             = $::redis::install::redis_group

  $redis_install_dir = $::redis::install::redis_install_dir
  $sentinel_init_script = $facts['os']['family'] ? {
    /(Debian|Ubuntu)/                                          => 'redis/etc/init.d/debian_redis-sentinel.erb',
    /(Fedora|RedHat|CentOS|OEL|OracleLinux|Amazon|Scientific)/ => 'redis/etc/init.d/redhat_redis-sentinel.erb',
    /(Gentoo)/                                                 => 'redis/etc/init.d/gentoo_redis-sentinel.erb',
    default                                                    => undef,
  }

  # redis conf file
  $conf_file_name = "redis-sentinel_${sentinel_name}.conf"
  $conf_file = "/etc/${conf_file_name}"
  file { $conf_file:
      ensure  => file,
      content => template('redis/etc/sentinel.conf.erb'),
      require => Class['redis::install'];
  }

  # startup script
  if ($facts['os']['family'] == 'RedHat' and versioncmp($facts['os']['release']['major'], '7') >=0 and $facts['os']['family'] != 'Amazon') {
    $service_file = "/usr/lib/systemd/system/redis-sentinel_${sentinel_name}.service"
    exec { "systemd_service_sentinel_${sentinel_name}_preset":
      command     => "/bin/systemctl preset redis-sentinel_${sentinel_name}.service",
      notify      => Service["redis-sentinel_${sentinel_name}"],
      refreshonly => true,
    }

    file { $service_file:
      ensure  => file,
      mode    => '0644',
      content => template('redis/systemd/sentinel.service.erb'),
      require => File[$conf_file],
      notify  => Exec["systemd_service_sentinel_${sentinel_name}_preset"],
    }
  } else {
    $service_file = "/etc/init.d/redis-sentinel_${sentinel_name}"
    file { $service_file:
      ensure  => file,
      mode    => '0644',
      content => template($sentinel_init_script),
      require => File[$conf_file],
      notify  => Service["redis-sentinel_${sentinel_name}"],
    }
  }

  # manage sentinel service
  service { "redis-sentinel_${sentinel_name}":
    ensure     => $running,
    enable     => $enabled,
    hasstatus  => true,
    hasrestart => true,
    subscribe  => File[$conf_file],
  }

  if ($manage_logrotate == true){
    # install and configure logrotate
    if ! defined(Package['logrotate']) {
      package { 'logrotate': ensure => installed; }
    }

    file { "/etc/logrotate.d/redis-sentinel_${sentinel_name}":
      ensure  => file,
      content => template('redis/sentinel_logrotate.conf.erb'),
      require => [
        Package['logrotate'],
        File["/etc/redis-sentinel_${sentinel_name}.conf"],
      ]
    }
  }
}
