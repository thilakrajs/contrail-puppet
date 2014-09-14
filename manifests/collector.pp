class contrail::collector {

    define collector-template-scripts {
        # Ensure template param file is present with right content.
        file { "/etc/contrail/${title}" :
            ensure  => present,
            require => Package["contrail-openstack-analytics"],
            content => template("$module_name/${title}.erb"),
        }
    }

    define contrail_collector () {
        case $::operatingsystem {
            Ubuntu: {
                  file {"/etc/init/supervisor-analytics.override": ensure => absent, require => Package['contrail-openstack-analytics']}
                  file { '/etc/init.d/supervisor-analytics':
                           ensure => link,
                     target => '/lib/init/upstart-job',
                     before => Service["supervisor-analytics"]
                  }


            }
        }

        # Ensure all needed packages are present
        package { 'contrail-openstack-analytics' : ensure => present,}

        # The above wrapper package should be broken down to the below packages
        # For Debian/Ubuntu - supervisor, python-contrail, contrail-analytics, contrail-setup, contrail-nodemgr
        # For Centos/Fedora - contrail-api-pib, contrail-analytics, contrail-setup, contrail-nodemgr

        # Ensure all config files with correct content are present.

        collector-template-scripts { ["contrail-analytics-api.conf" , "contrail-collector.conf", "contrail-query-engine.conf"]: }

        exec { "redis-conf-exec":
            command => "sed -i -e '/^[ ]*bind/s/^/#/' /etc/redis/redis.conf;chkconfig redis-server on; service redis-server restart && echo redis-conf-exec>> /etc/contrail/contrail-collector-exec.out",
            onlyif => "test -f /etc/redis/redis.conf",
            unless  => "grep -qx redis-conf-exec /etc/contrail/contrail-collector-exec.out",
            provider => shell,
            logoutput => "true"
        }

        # Ensure the services needed are running.
        service { "supervisor-analytics" :
            enable => true,
            require => [ Package['contrail-openstack-analytics']
                       ],
            subscribe => [ File['/etc/contrail/contrail-collector.conf'],
                           File['/etc/contrail/contrail-query-engine.conf'],
                           File['/etc/contrail/contrail-analytics-api.conf'] ],
            ensure => running,
        }
    }
}
