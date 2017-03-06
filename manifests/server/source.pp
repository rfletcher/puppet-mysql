class mysql::server::source{
  $override_options        = hiera_hash( "mysql::server::override_options", {} )
  $override_mysqld_options = pickx( $override_options['mysqld'], {} )

  $description    = "MySQL Server"
  $source         = $mysql::server::source
  $source_md5     = $mysql::server::source_md5
  $module_basedir = $mysql::params::basedir
  $mysqld_basedir = $override_mysqld_options['basedir']

  if $source != undef and
     ( $mysql::server::package_manage == false or $mysql::server::package_ensure == 'absent' ) {
    $use_source = true
  } else {
    $use_source = false
  }

  if $use_source {
    if( $mysqld_basedir == undef ) {
      crit( 'If mysql::source is set, you must also set mysql::server::override_options[\'mysqld\'][\'basedir\']' )
    }

    $source_filename = basename( $source, '.tar.gz' )
    $source_version  = regsubst( $source_filename, '.*mysql-(\d+\.\d+).*', '\1' )

    $archive_basedir = "/usr/local/mysql"
    $archive_dir     = "${archive_basedir}/${source_filename}"

    # install dependencies

    package { 'libaio1':
      ensure => present,
      before => Service['mysqld'],
    }

    # install mysql server

    archive { $source_filename:
      checksum      => $source_md5 ? { undef => false, default => true, },
      digest_string => $source_md5,
      target        => $archive_basedir,
      url           => $source,
      before        => [
        File[$archive_dir],
        File[$mysqld_basedir],
        File['/var/log/mysql'],
      ]
    }

    user { 'mysql':
      ensure  => present,
      comment => $description,
      home    => '/nonexistent',
      groups  => $mysql::params::mysql_group ? { 'mysql' => undef, default => [$mysql::params::mysql_group], },
      shell   => '/bin/false',
      system  => true,
      before  => Service['mysqld'],
    }

    $mysqld_basedir_parent = dirname( $mysqld_basedir )

    exec { "mkdir -p ${mysqld_basedir_parent}":
      creates => $mysqld_basedir_parent,
    } ->

    file { $mysqld_basedir:
      ensure  => link,
      target  => $archive_dir,
      before  => Systemd::Service['mysql'],
      # notify  => Exec['set initial mysql password'],
    }

    # create a bunch of directories that a proper packsge would have created for us

    file { [
      $mysql::params::datadir,
      dirname( $mysql::params::pidfile ),
    ]:
      ensure  => directory,
      group   => $mysql::params::mysql_group,
      owner   => 'mysql',
      require => User['mysql'],
      before  => Service['mysqld'],
    }

    file { [
      $archive_dir,
      "${module_basedir}/mysql",
      "${module_basedir}/share/mysql",
      dirname( $mysql::params::log_error ),
    ]:
      ensure  => directory,
      force   => true,
      group   => $mysql::params::mysql_group,
      owner   => 'mysql',
      recurse => true,
      require => User['mysql'],
      before  => Service['mysqld'],
    }

    # link to binaries and scripts where they're normally expected

    file { '/usr/local/bin/mysql':
      ensure => link,
      tag    => "mysql-binary",
      target => "${mysqld_basedir}/bin/mysql",
    }

    file { '/usr/local/bin/mysqld':
      ensure => link,
      tag    => "mysql-binary",
      target => "${mysqld_basedir}/bin/mysqld",
    }

    file { '/usr/local/bin/mysqladmin':
      ensure => link,
      tag    => "mysql-binary",
      target => "${mysqld_basedir}/bin/mysqladmin",
    }

    file { "${module_basedir}/share/mysql/scripts":
      ensure  => link,
      tag     => "mysql-binary",
      target  => "${mysqld_basedir}/scripts",
      require => File["${module_basedir}/share/mysql"],
    }

    File <| tag == "mysql-binary" |> -> Mysql_database <| |>
    File <| tag == "mysql-binary" |> -> Mysql_datadir <| |>
    File <| tag == "mysql-binary" |> -> Mysql_grant <| |>
    File <| tag == "mysql-binary" |> -> Mysql_plugin <| |>
    File <| tag == "mysql-binary" |> -> Mysql_user<| |>

    # configure the system service

    ::systemd::service { 'mysql':
      ensure      => present,
      after       => ['network-online.target'],
      description => $description,
      execstart   => "${mysqld_basedir}/bin/mysqld",
      group       => $mysql::params::mysql_group,
      restart     => 'on-failure',
      type        => 'simple',
      user        => 'mysql',
      before      => Service['mysqld'],
      require     => User['mysql'],
    }
  }
}
