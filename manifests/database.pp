class contrail::database {



    define database-scripts {
        file { "/opt/contrail/contrail_installer/contrail_setup_utils/${title}.sh":
            ensure  => present,
            mode => 0755,
            owner => root,
            group => root,
        }
        exec { "setup-${title}" :
            command => "/opt/contrail/contrail_installer/contrail_setup_utils/${title}.sh; echo setup-${title} >> /etc/contrail/contrail-compute-exec.out",
            require => File["/opt/contrail/contrail_installer/contrail_setup_utils/${title}.sh"],
            unless  => "grep -qx setup-${title} /etc/contrail/contrail-compute-exec.out",
            provider => shell,
            logoutput => "true"
        }
    }

    define fix-upstart ($contrail_os) {
        # Below is temporary to work-around in Ubuntu as Service resource fails
        # as upstart is not correctly linked to /etc/init.d/service-name
        if ($operatingsystem == "Ubuntu") {
            file { '/etc/init.d/supervisord-contrail-database':
                ensure => link,
                target => '/lib/init/upstart-job',
                before => Service["supervisord-contrail-database"]
            }
        }

    }

    define database-template-scripts {
        $contrail_config_ip = $::openstack::config::contrail::config_ip
        # Ensure template param file is present with right content.
        file { "/etc/contrail/${title}" :
            ensure  => present,
        before => Service["supervisord-contrail-database"],
            content => template("$module_name/${title}.erb"),
        }
    }

    define contrail_database (
        ) {
        notify { "contrail cassandra dir is $contrail_config_ip":; }
        case $::operatingsystem {
            Ubuntu: {
                $contrail_cassandra_dir = "/etc/cassandra"
                file {"/etc/init/supervisord-contrail-database.override":
                ensure => absent,
                require => Package['contrail-openstack-database']}

            }
            Centos: {
                $contrail_cassandra_dir = "/etc/cassandra/conf"
            }
            Fedora: {
                $contrail_cassandra_dir = "/etc/cassandra/conf"
            }
            default: {
                 $contrail_cassandra_dir = "/etc/cassandra/conf"
            }
        }
        $contrail_zk_ip_list_for_shell = inline_template('<%= contrail_zookeeper_ip_list.map{ |ip| "#{ip}" }.join(" ") %>')
        $contrail_zk_exec_cmd = "/bin/bash /etc/contrail/contrail_setup_utils/config-zk-files-setup.sh $operatingsystem $contrail_cfgm_index $contrail_zk_ip_list_for_shell && echo setup-config-zk-files-setup >> /etc/contrail/contrail-config-exec.out"

        # Ensure all needed packages are present
        package { 'contrail-openstack-database' : ensure => present,}
        # The above wrapper package should be broken down to the below packages
        # For Debian/Ubuntu - cassandra (>= 1.1.12) , contrail-setup, supervisor
        # For Centos/Fedora - contrail-api-lib, contrail-database, contrail-setup, openstack-quantum-contrail, supervisor
        ->
        exec { "exec-config-host-entry" :
            command   => 'echo \"$contrail_config_ip   $system_name\" >> /etc/hosts && echo exec-config-host-entry >> /etc/contrail/contrail_database_exec.out',
            unless    => ["grep -q $contrail_config_ip /etc/hosts",
                          "grep -qx exec-config-host-entry /etc/contrail/contrail_database_exec.out"],
            provider => "shell",
            require => Package['contrail-openstack-database'],
            logoutput => "true"
        }
        ->
        # database venv installation
        exec { "database-venv" :
            command   => '/bin/bash -c "source ../bin/activate && pip install * && echo database-venv >> /etc/contrail/contrail_database_exec.out"',
            cwd       => '/opt/contrail/database-venv/archive',
            unless    => [ "[ ! -d /opt/contrail/database-venv/archive ]",
                           "[ ! -f /opt/contrail/database-venv/bin/activate ]",
                           "grep -qx database-venv /etc/contrail/contrail_database_exec.out"],
            require   => Package['contrail-openstack-database'],
            provider => "shell",
            logoutput => "true"
        }
        ->
        notify { "contrail cassandra dir is $contrail_cassandra_dir":; }
        ->
        file { "$contrail_database_dir" :
            ensure  => directory,
            require => Package['contrail-openstack-database']
        }
        ->
        file { "$contrail_cassandra_dir/cassandra.yaml" :
            ensure  => present,
            require => [ Package['contrail-openstack-database'] ],
            content => template("$module_name/cassandra.yaml.erb"),
        }
        ->
        file { "$contrail_cassandra_dir/cassandra-env.sh" :
            ensure  => present,
            require => [ Package['contrail-openstack-database'] ],
            content => template("$module_name/cassandra-env.sh.erb"),
        }
        ->
        fix-upstart {fix_upstart:
        contrail_os => $operatingsystem
        }
        ->
        # set high session timeout to survive glance led disk activity
        file { "/etc/contrail/contrail_setup_utils/config-zk-files-setup.sh":
            ensure  => present,
            mode => 0755,
            owner => root,
            group => root,
            require => Package["contrail-openstack-database"],
            source => "puppet:///modules/$module_name/config-zk-files-setup.sh"
        }
        ->
        notify { "contrail contrail_zk_exec_cmd is $contrail_zk_exec_cmd":; }
        ->
        exec { "setup-config-zk-files-setup" :
            command => $contrail_zk_exec_cmd,
            require => File["/etc/contrail/contrail_setup_utils/config-zk-files-setup.sh"],
            unless  => "grep -qx setup-config-zk-files-setup /etc/contrail/contrail-config-exec.out",
            provider => shell,
            logoutput => "true"
        }
        ->
        database-template-scripts { ["contrail-nodemgr-database.conf", "database_nodemgr_param"]: }
        ->
        database-scripts { ["database-server-setup"]: }
        ->
        # Ensure the services needed are running.
        service { "supervisord-contrail-database" :
            enable => true,
            require => [ Package["contrail-openstack-database"],
                         Exec['database-venv'] ],
            subscribe => [ File["$contrail_cassandra_dir/cassandra.yaml"],
                           File["$contrail_cassandra_dir/cassandra-env.sh"] ],
            ensure => running,
        }

     }
}
