# Class: elasticsearch
#
# This class installs Elasticsearch
#
# Usage:
# include elasticsearch

class elasticsearch($version = "0.19.11", $xmx = "1024") {
  $esBasename       = "elasticsearch"
  $esName           = "${esBasename}-${version}"
  $esFile           = "${esName}.tar.gz"
  $esServiceName    = "${esBasename}-servicewrapper"
  $esServiceFile    = "${esServiceName}.tar.gz"
  $esPath           = "/usr/local/${esName}"
  $esPathLink       = "/usr/local/${esBasename}"
  $esDataPath       = "/var/lib/${esBasename}"
  $esLibPath        = "${esDataPath}"
  $esLogPath        = "/var/log/${esBasename}"
  $esXms            = "256"
  $esXmx            = "${xmx}"
  $cluster          = "${esBasename}"
  $esTCPPortRange   = "9300-9399"
  $esHTTPPortRange  = "9200-9299"
  $esUlimitNofile   = "32000"
  $esUlimitMemlock  = "unlimited"
  $esPidpath        = "/var/run"
  $esPidfile        = "${esPidpath}/${esBasename}.pid"
  $esJarfile        = "${esName}.jar"

  include Java

  # Ensure the elasticsearch user is present
  user { "$esBasename":
    ensure      => "present",
    comment     => "Elasticsearch user created by puppet",
    managehome  => true,
    shell       => "/bin/false",
    uid         => 901,
  }

 file { "/etc/security/limits.d/${esBasename}.conf":
   content  => template("elasticsearch/elasticsearch.limits.conf.erb"),                                                                                                    
   ensure   => present,
   owner    => root,
   group    => root,
 }

  # Make sure we have the application path
  file { "$esPath":
    ensure     => directory,
    require    => User["$esBasename"],
    owner      => "$esBasename",
    group      => "$esBasename", 
    recurse    => true,
  }

  # Make sure we have the work path
  file { "$esPath/work":
    ensure     => directory,
    require    => [ File["$esPath"], User["$esBasename"] ],
    owner      => "$esBasename",
    group      => "$esBasename", 
  }

  # Make sure we have the log path
  file { "$esPath/work/logs":
    ensure     => directory,
    require    => [ File["$esPath/work"], User["$esBasename"] ],
    owner      => "$esBasename",
    group      => "$esBasename",
  }

  # Make sure we have the source path
  file { "$esPath/src":
    ensure     => directory,
    require    => User["$esBasename"],
    owner      => "$esBasename",
    group      => "$esBasename", 
    recurse    => true
  }

  # Source file
  exec { "$esPath/src/$esFile":
    path        => "/bin:/usr/bin:/usr/local/bin",
    cwd         => "$esPath/src",
    command     => "wget -q https://github.com/downloads/elasticsearch/elasticsearch/$esFile -O $esFile",
    creates     => "$esPath/src/$esFile",
    require     => File["$esPath/src"],
    notify      => Exec["elasticsearch-package"],
  }

  # Remove old files and copy in latest
  exec { "elasticsearch-package":
    path          => "/bin:/usr/bin",
    command       => "tar -xzf $esPath/src/$esFile -C $esPath", 
    refreshonly   => true,
    notify        => Service["$esBasename"],
  }

  ## Note: this is a bit hackish, need to stop the old elasticsearch when upgrading
  exec { "stop-elasticsearch-version-change":
    command => "service elasticsearch stop",
    unless  => "ps aux | grep ${esName} | grep -v grep",
    onlyif  => "ps aux | grep ${esBasename} | grep -v grep",
    require => Exec["elasticsearch-package"],
    notify  => Service["$esBasename"],
    path    => ["/bin", "/sbin", "/usr/bin", "/usr/sbin"],
  }

  # Create link to /usr/local/<esBasename> which will be the current version
  file { "$esPathLink":
    ensure  => link,
    target  => "$esPath/$esName",
    require => Exec["stop-elasticsearch-version-change"],
  }

  # Ensure the data path is created
  file { "$esDataPath":
    ensure  => directory,
    owner   => "$esBasename",
    group   => "$esBasename",
    require => Exec["elasticsearch-package"],
    recurse => true,
  }

  # Ensure the link to the data path is set
  file { "$esPath/data":
    ensure  => link,
    force   => true,
    target  => "$esDataPath",
    require => File["$esDataPath"],
  }

  # Symlink config to /etc
  file { "/etc/$esBasename":
    ensure  => link,
    target  => "$esPathLink/config",
    require => Exec["elasticsearch-package"],
  }

  # Make sure we have the config path
  file { "$esPath/config":
    ensure     => directory,
    require    => User["$esBasename"],
    owner      => "$esBasename",
    group      => "$esBasename", 
    recurse    => true
  }

  # Apply config template for search
  file { "$esPath/config/elasticsearch.yml":
    content => template("elasticsearch/elasticsearch.yml.erb"),
    require => File["$esPath/config"],
  }

  # Create startup script
  file { "/etc/init.d/elasticsearch":
    ensure  => link,
    source  => "puppet:///modules/elasticsearch/elasticsearch",
  }

  # Ensure logging directory
  file { "$esLogPath":
    owner     => "$esBasename",
    group     => "$esBasename",
    ensure    => directory,
    recurse   => true,
    require   => Exec["elasticsearch-package"],
  }

  # Ensure the service is running
  service { "$esBasename":
    enable      => true,
    ensure      => running,
    hasrestart  => true,
    require     => [ File["$esLogPath"], File["/etc/init.d/elasticsearch"] ],
  }

}
