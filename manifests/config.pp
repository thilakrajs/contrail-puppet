class contrail::config {

    # Macro to push and execute certain scripts.
    define config-scripts {
        file { "/opt/contrail/contrail_installer/contrail_setup_utils/${title}.sh":
            ensure  => present,
            mode => 0755,
            owner => root,
            group => root,
            require => [File["/etc/contrail/ctrl-details"],Config-template-scripts["schema_transformer.conf"],Config-template-scripts["svc_monitor.conf"]]
        }
        exec { "setup-${title}" :
            command => "/bin/bash /opt/contrail/contrail_installer/contrail_setup_utils/${title}.sh $operatingsystem && echo setup-${title} >> /etc/contrail/contrail_config_exec.out",
            require => File["/opt/contrail/contrail_installer/contrail_setup_utils/${title}.sh"],
            unless  => "grep -qx setup-${title} /etc/contrail/contrail_config_exec.out",
            provider => shell
        }
    }

    # Macro to setup the configuration files from templates.
    define config-template-scripts {
        if $contrail_use_certs == "yes" {
            $contrail_ifmap_server_port = '8444'
        }
        else {
            $contrail_ifmap_server_port = '8443'
        }

        # Ensure template param file is present with right content.
        file { "/etc/contrail/${title}" :
            ensure  => present,
            require => Package["contrail-openstack-config"],
        notify =>  Service["supervisor-config"],
            content => template("$module_name/${title}.erb"),
        }
    }





    define fix_rabbitmq_conf() {
	if($internal_vip != "") {
	    exec { "rabbit_os_fix":
		command => "rabbitmqctl set_policy HA-all \"\" '{\"ha-mode\":\"all\",\"ha-sync-mode\":\"automatic\"}' && echo rabbit_os_fix >> /etc/contrail/contrail_openstack_exec.out",
                require => package["contrail-openstack-ha"],
                unless  => "grep -qx rabbit_os_fix /etc/contrail/contrail_openstack_exec.out",
                provider => shell,
                logoutput => "true"
            }

	}

	if ! defined(File["/opt/contrail/contrail_installer/set_rabbit_tcp_params.py"]) {

	    # check_wsrep
	    file { "/opt/contrail/contrail_installer/set_rabbit_tcp_params.py" :
		ensure  => present,
		mode => 0755,
		group => root,
		source => "puppet:///modules/$module_name/set_rabbit_tcp_params.py"
	    }


	    exec { "exec_set_rabbitmq_tcp_params" :
		command => "python /opt/contrail/contrail_installer/set_rabbit_tcp_params.py",
		cwd => "/opt/contrail/contrail_installer/",
		unless  => "grep -qx exec_set_rabbitmq_tcp_params /etc/contrail/contrail_openstack_exec.out",
		provider => shell,
		require => [ File["/opt/contrail/contrail_installer/set_rabbit_tcp_params.py"] ],
		logoutput => 'true'
	    }
	}

    }


    define build-ctrl-details($contrail_haproxy,
                  $contrail_ks_auth_protocol="http",
                  $contrail_quantum_service_protocol="http",
                  $contrail_config_ip) {
        # Ensure ctrl-details file is present with right content.
        if ! defined(File["/etc/contrail/ctrl-details"]) {
            $quantum_port = "9697"
             if $contrail_haproxy == "enable" {
            $quantum_ip = "127.0.0.1"
            } else {
            $quantum_ip = $contrail_config_ip
            }
	    if ($internal_vip == undef) {
                $internal_vip = "none"
            }
            if ($external_vip == undef) {
                $external_vip = "none"
            }
            if ($contrail_internal_vip == undef) {
                $contrail_internal_vip = "none"
            }
            if ($contrail_external_vip == undef) {
                $contrail_external_vip = "none"
            }


            file { "/etc/contrail/ctrl-details" :
                ensure  => present,
                content => template("$module_name/ctrl-details.erb"),
            }
        }
    }

    define setup-pki($contrail_use_certs) {
        # run setup-pki.sh script
        if $contrail_use_certs == true {
            file { "/etc/contrail_setup_utils/setup-pki.sh" :
                ensure  => present,
                mode => 0755,
                user => root,
                group => root,
                source => "puppet:///modules/$module_name/setup-pki.sh"
            }
            exec { "setup-pki" :
                command => "/etc/contrail_setup_utils/setup-pki.sh /etc/contrail/ssl; echo setup-pki >> /etc/contrail/contrail_config_exec.out",
                require => File["/etc/contrail_setup_utils/setup-pki.sh"],
                unless  => "grep -qx setup-pki /etc/contrail/contrail_config_exec.out",
                provider => shell,
                logoutput => "true"
            }
        }
    }

    define setup-rabbitmq-cluster($contrail_uuid,
                    $contrail_rmq_master,
                    $contrail_rmq_is_master
                    ) {

        # Handle rabbitmq.config changes
        $conf_file = "/etc/rabbitmq/rabbitmq.config"
        file { "/etc/contrail/contrail_setup_utils/cfg-rabbitmq.sh" :
            ensure  => present,
            mode => 0755,
            owner => root,
            group => root,
            require => Package['contrail-openstack-config'],
            source => "puppet:///modules/$module_name/cfg-qpidd-rabbitmq.sh"
        }
        exec { "exec-cfg-rabbitmq" :
            command => "/bin/bash /etc/contrail/contrail_setup_utils/cfg-rabbitmq.sh $conf_file $host_ip $contrail_rabbit_user $contrail_cfgm_number && echo exec-cfg-rabbitmq >> /etc/contrail/contrail_config_exec.out",
            require =>  File["/etc/contrail/contrail_setup_utils/cfg-rabbitmq.sh"],
            unless  => "grep -qx exec-cfg-rabbitmq /etc/contrail/contrail_config_exec.out",
            provider => shell,
            logoutput => 'true'
        }

        file { "/etc/contrail/contrail_setup_utils/setup_rabbitmq_cluster.sh":
            ensure  => present,
            mode => 0755,
            owner => root,
            group => root,
            require => Package["contrail-openstack-config"],
            source => "puppet:///modules/$module_name/setup_rabbitmq_cluster.sh"
        }

        exec { "setup-rabbitmq-cluster" :
            command => "/bin/bash /etc/contrail/contrail_setup_utils/setup_rabbitmq_cluster.sh $operatingsystem $contrail_uuid $contrail_rmq_master $contrail_rmq_is_master '$contrail_rabbithost_list_for_shell' && echo setup_rabbitmq_cluster >> /etc/contrail/contrail_config_exec.out",
            require => File["/etc/contrail/contrail_setup_utils/setup_rabbitmq_cluster.sh"],
            unless  => "grep -qx setup_rabbitmq_cluster /etc/contrail/contrail_config_exec.out",
            provider => shell,
            logoutput => "true"
        }


        file { "/etc/contrail/contrail_setup_utils/check_rabbitmq_cluster.sh":
            ensure  => present,
            mode => 0755,
            owner => root,
            group => root,
            require => Package["contrail-openstack-config"],
            source => "puppet:///modules/$module_name/check_rabbitmq_cluster.sh"
        }
        notify { $contrail_rabbit_user:; }

        $contrail_rabbithost_list_for_shell = inline_template('<%= contrail_rabbit_user.gsub(/\,/, " ").delete "[]" %>')

        notify { $contrail_rabbithost_list_for_shell:; }
        #Check to see if the rabbitmq cluster is fully formed,
        #else dont process in the chain
        exec { "check-rabbitmq-cluster" :
            command => "/bin/bash /etc/contrail/contrail_setup_utils/check_rabbitmq_cluster.sh '$contrail_rabbithost_list_for_shell' && echo check_rabbitmq_cluster >> /etc/contrail/contrail_config_exec.out",
            require => File["/etc/contrail/contrail_setup_utils/check_rabbitmq_cluster.sh"],
            unless  => "grep -qx check_rabbitmq_cluster /etc/contrail/contrail_config_exec.out",
            provider => shell,
            logoutput => "true"
        }
    }


    define form-service-token {
        $keystone_admin_token = $keystone_admin_token
        # Ensure service.token file is present with right content.
        if ! defined(File["/etc/contrail/service.token"]) {
            file { "/etc/contrail/service.token" :
                ensure  => present,
                content => template("$module_name/service.token.erb"),
            }
        }
    }

    define form-neutron-conf {
        if ! defined(Exec["neutron-conf-exec"]) {
            exec { "neutron-conf-exec":
                command => "sudo sed -i 's/rpc_backend\s*=\s*neutron.openstack.common.rpc.impl_qpid/#rpc_backend = neutron.openstack.common.rpc.impl_qpid/g' /etc/neutron/neutron.conf && echo neutron-conf-exec >> /etc/contrail/contrail_openstack_exec.out",
                onlyif => "test -f /etc/neutron/neutron.conf",
                unless  => "grep -qx neutron-conf-exec /etc/contrail/contrail_openstack_exec.out",
                provider => shell,
                logoutput => "true"
            }
        }
    }

    define contrail_config (
            $contrail_ks_insecure_flag=false,
            $contrail_hc_interval="5",
            $contrail_ks_auth_protocol="http",
            $contrail_quantum_service_protocol="http",
            $contrail_ks_auth_port="35357"
        ) {
        if $contrail_use_certs == "yes" {
            $contrail_ifmap_server_port = '8444'
        }
        else {
            $contrail_ifmap_server_port = '8443'
        }

        if $contrail_multi_tenancy == "True" {
            $contrail_memcached_opt = "memcache_servers=127.0.0.1:11211"
        }
        else {
            $contrail_memcached_opt = ""
        }
        # Initialize the multi tenancy option will update latter based on vns argument
        if ($contrail_multi_tenancy == "True") {
        $mt_options = "admin,$::openstack::config::keystone_admin_password,$contrail_ks_admin_tenant"
        } else {
            $mt_options = "None"
        }



        # Supervisor contrail-api.ini
        $contrail_api_port_base = '910'
        # Supervisor contrail-discovery.ini
        $contrail_disc_port_base = '911'
        $contrail_disc_nworkers = '1'

        $contrail_host_ip_list_for_shell = inline_template('<%= contrail_control_ip_list.map{ |ip| "#{ip}" }.join(",") %>')
        $contrail_host_name_list_for_shell = inline_template('<%= contrail_control_name_list.map{ |name| "#{name}" }.join(",") %>')
        $contrail_exec_provision_control = "python  exec_provision_control.py --api_server_ip $contrail_config_ip --api_server_port 8082 --host_name_list $contrail_host_name_list_for_shell --host_ip_list $contrail_host_ip_list_for_shell --router_asn $contrail_router_asn --mt_options $mt_options && echo exec-provision-control >> /etc/contrail/contrail_config_exec.out"

        case $::operatingsystem {
            Ubuntu: {
                          #  notify { "OS is Ubuntu":; }
            file {"/etc/init/supervisor-config.override": ensure => absent, require => Package['contrail-openstack-config']}
            file {"/etc/init/neutron-server.override": ensure => absent, require => Package['contrail-openstack-config']}

            file { "/etc/contrail/supervisord_config_files/contrail-api.ini" :
                ensure  => present,
                require => Package["contrail-openstack-config"],
                content => template("$module_name/contrail-api.ini.erb"),
            }

            file { "/etc/contrail/supervisord_config_files/contrail-discovery.ini" :
                ensure  => present,
                require => Package["contrail-openstack-config"],
                content => template("$module_name/contrail-discovery.ini.erb"),
            }

        # Below is temporary to work-around in Ubuntu as Service resource fails
        # as upstart is not correctly linked to /etc/init.d/service-name
            file { '/etc/init.d/supervisor-config':
                ensure => link,
                target => '/lib/init/upstart-job',
                before => Service["supervisor-config"]
            }


            }
            Centos: {
                           # notify { "OS is Ubuntu":; }
            file { "/etc/contrail/supervisord_config_files/contrail-api.ini" :
                ensure  => present,
                require => Package["contrail-openstack-config"],
                content => template("$module_name/contrail-api-centos.ini.erb"),
            }

            file { "/etc/contrail/supervisord_config_files/contrail-discovery.ini" :
                ensure  => present,
                require => Package["contrail-openstack-config"],
                content => template("$module_name/contrail-discovery-centos.ini.erb"),
            }

            }
            Fedora: {
                    #        notify { "OS is Ubuntu":; }
            file { "/etc/contrail/supervisord_config_files/contrail-api.ini" :
                ensure  => present,
                require => Package["contrail-openstack-config"],
                content => template("$module_name/contrail-api-centos.ini.erb"),
            }

            file { "/etc/contrail/supervisord_config_files/contrail-discovery.ini" :
                ensure  => present,
                require => Package["contrail-openstack-config"],
                content => template("$module_name/contrail-discovery-centos.ini.erb"),
            }



            }
            default: {
                     #       notify { "OS is $operatingsystem":; }

            }
        }


        # Ensure all needed packages are present
        package { 'contrail-openstack-config' : ensure => present,}
        # The above wrapper package should be broken down to the below packages
        # For Debian/Ubuntu - supervisor, contrail-nodemgr, contrail-lib, contrail-config, neutron-plugin-contrail, neutron-server, python-novaclient,
        #                     python-keystoneclient, contrail-setup, haproxy, euca2ools, rabbitmq-server, python-qpid, python-iniparse, python-bottle,
        #                     zookeeper, ifmap-server, ifmap-python-client, contrail-config-openstack
        # For Centos/Fedora - contrail-api-lib contrail-api-extension, contrail-config, openstack-quantum-contrail, python-novaclient, python-keystoneclient >= 0.2.0,
        #                     python-psutil, mysql-server, contrail-setup, python-zope-interface, python-importlib, euca2ools, m2crypto, openstack-nova,
        #                     java-1.7.0-openjdk, haproxy, rabbitmq-server, python-bottle, contrail-nodemgr
        ->
        build-ctrl-details{build_ctrl_details:
            contrail_haproxy => $contrail_haproxy,
            contrail_config_ip => $contrail_config_ip}
        ->
        form-service-token{form_service_token:}
        ->
        form-neutron-conf{from_neturon_conf:}
        ->

        # Ensure log4j.properties file is present with right content.
        file { "/etc/ifmap-server/log4j.properties" :
            ensure  => present,
            require => Package["contrail-openstack-config"],
            content => template("$module_name/log4j.properties.erb"),
        }
        ->
        # Ensure authorization.properties file is present with right content.
        file { "/etc/ifmap-server/authorization.properties" :
            ensure  => present,
            require => Package["contrail-openstack-config"],
            content => template("$module_name/authorization.properties.erb"),
        }
        ->
        # Ensure basicauthusers.proprties file is present with right content.
        file { "/etc/ifmap-server/basicauthusers.properties" :
            ensure  => present,
            require => Package["contrail-openstack-config"],
            content => template("$module_name/basicauthusers.properties.erb"),
        }
        ->
        # Ensure publisher.properties file is present with right content.
        file { "/etc/ifmap-server/publisher.properties" :
            ensure  => present,
            require => Package["contrail-openstack-config"],
            content => template("$module_name/publisher.properties.erb"),
        }
        ->
        # Ensure all config files with correct content are present.
        config-template-scripts { ["contrail-api.conf",
                                   "schema_transformer.conf",
                                   "svc_monitor.conf",
                                   "contrail-discovery.conf",
                                   "vnc_api_lib.ini",
                                   "contrail_plugin.ini"]: }

        ->
        # initd script wrapper for contrail-api
        file { "/etc/init.d/contrail-api" :
            ensure  => present,
            mode => 0777,
            require => Package["contrail-openstack-config"],
            content => template("$module_name/contrail-api.svc.erb"),
        }
        ->
        exec { "create-contrail-plugin-neutron":
            command => "cp /etc/contrail/contrail_plugin.ini /etc/neutron/plugins/opencontrail/ContrailPlugin.ini",
            require => File["/etc/contrail/contrail_plugin.ini"],
            onlyif => "test -d /etc/neutron/",
            provider => shell,
            logoutput => "true"
        }
        ->
        exec { "create-contrail-plugin-quantum":
            command => "cp /etc/contrail/contrail_plugin.ini /etc/quantum/plugins/contrail/contrail_plugin.ini",
            require => File["/etc/contrail/contrail_plugin.ini"],
            onlyif => "test -d /etc/quantum/",
            provider => shell,
            logoutput => "true"
        }

        ->
        # initd script wrapper for contrail-discovery
        file { "/etc/init.d/contrail-discovery" :
            ensure  => present,
            mode => 0777,
            require => Package["contrail-openstack-config"],
            content => template("$module_name/contrail-discovery.svc.erb"),
        }
        ->
        setup-rabbitmq-cluster{setup_rabbitmq_cluster:
                    contrail_uuid => $contrail_uuid,
                    contrail_rmq_master => $contrail_rmq_master,
                    contrail_rmq_is_master => $contrail_rmq_is_master
                    }

        ->
        fix_rabbitmq_conf{fix_rabbitmq_conf:}
        ->
        setup-pki{setup_pki:
            contrail_use_certs => $contrail_use_certs}
        ->
        # Execute config-server-setup scripts
        config-scripts { ["config-server-setup", "quantum-server-setup"]: }
        ->

        file { "/etc/contrail/contrail_setup_utils/exec_provision_control.py" :
            ensure  => present,
            mode => 0755,
            group => root,
            source => "puppet:///modules/$module_name/exec_provision_control.py"
        }
        ->
        notify { "contrail contrail_exec_provision_control is $contrail_exec_provision_control":; }
        ->
        exec { "exec-provision-control" :
            command => $contrail_exec_provision_control,
            cwd => "/etc/contrail/contrail_setup_utils/",
            unless  => "grep -qx exec-provision-control /etc/contrail/contrail_config_exec.out",
            provider => shell,
        require => [ File["/etc/contrail/contrail_setup_utils/exec_provision_control.py"] ],
            logoutput => 'true'
        }
        ->
        file { "/etc/contrail/contrail_setup_utils/setup_external_bgp.py" :
                ensure  => present,
                mode => 0755,
                group => root,
                source => "puppet:///modules/$module_name/setup_external_bgp.py"
        }
        ->
       exec { "provision-external-bgp" :
            command => "python /etc/contrail/contrail_setup_utils/setup_external_bgp.py --bgp_params \"$contrail_bgp_params\" --api_server_ip $contrail_config_ip --api_server_port 8082 --router_asn $contrail_router_asn --mt_options \"$mt_options\" && echo provision-external-bgp >> /etc/contrail/contrail_config_exec.out",
            require => [ File["/etc/contrail/contrail_setup_utils/setup_external_bgp.py"] ],
            unless  => "grep -qx provision-external-bgp /etc/contrail/contrail_config_exec.out",
            provider => shell,
            logoutput => "true"
        }
        ->
        exec { "provision-metadata-services" :
            command => "python /opt/contrail/utils/provision_linklocal.py --admin_user $contrail_ks_admin_user --admin_password $::openstack::config::keystone_admin_password --linklocal_service_name metadata --linklocal_service_ip 169.254.169.254 --linklocal_service_port 80 --ipfabric_service_ip $::openstack::config::controller_address_api  --ipfabric_service_port 8775 --oper add && echo provision-metadata-services >> /etc/contrail/contrail_config_exec.out",
            unless  => "grep -qx provision-metadata-services /etc/contrail/contrail_config_exec.out",
            provider => shell,
            logoutput => "true"
        }
        ->
        exec { "provision-encap-type" :
            command => "python /opt/contrail/utils/provision_encap.py --admin_user $contrail_ks_admin_user --admin_password $::openstack::config::keystone_admin_password --encap_priority $contrail_encap_priority --oper add && echo provision-encap-type >> /etc/contrail/contrail_config_exec.out",
            unless  => "grep -qx provision-encap-type /etc/contrail/contrail_config_exec.out",
            provider => shell,
            logoutput => "true"
        }
        ->
        service { "supervisor-config" :
            enable => true,
            require => [ Package['contrail-openstack-config']],
            ensure => running,
        }
    }
    # end of user defined type contrail_config.

}
