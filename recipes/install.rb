require 'json'
require 'base64'

private_ip=my_private_ip()
username=node['hopsworks']['admin']['user']
password=node['hopsworks']['admin']['password']
domain_name="domain1"
domains_dir = node['hopsworks']['domains_dir']
theDomain="#{domains_dir}/#{domain_name}"
admin_port = node['glassfish']['admin']['port']
web_port = node['glassfish']['port']
mysql_user=node['mysql']['user']
mysql_password=node['mysql']['password']
mysql_host = my_private_ip()
password_file = "#{theDomain}_admin_passwd"


bash "systemd_reload_for_glassfish_failures" do
  user "root"
  code <<-EOF
    systemctl daemon-reload
  EOF
end


if node['hopsworks']['systemd'] === "true" 
  systemd = true
else
  systemd = false
end

group node['hopsworks']['group'] do
  action :create
  not_if "getent group #{node['hopsworks']['group']}"
end

group node['jupyter']['group'] do
  action :create
  not_if "getent group #{node['jupyter']['group']}"
end

#
# hdfs superuser group is 'hdfs'
#
group node['hops']['hdfs']['user'] do
  action :create
  not_if "getent group #{node['hops']['hdfs']['user']}"
end

user node['hopsworks']['user'] do
  home "/home/#{node['hopsworks']['user']}"
  gid node['hopsworks']['group']
  action :create
  shell "/bin/bash"
  manage_home true
  not_if "getent passwd #{node['hopsworks']['user']}"
end

group node['jupyter']['group'] do
  action :modify
  members ["#{node['hopsworks']['user']}"]
  append true
end

# Add to the hdfs superuser group
group node['hops']['hdfs']['user'] do
  action :modify
  members ["#{node['hopsworks']['user']}"]
  append true
end

user node['jupyter']['user'] do
  home node['jupyter']['base_dir']
  gid node['jupyter']['group']  
  action :create
  shell "/bin/bash"
  manage_home true
  not_if "getent passwd #{node['jupyter']['user']}"
end

group node['kagent']['certs_group'] do
  action :modify
  members ["#{node['hopsworks']['user']}", "#{node['jupyter']['user']}"]
  append true
end

group node['hops']['group'] do
  action :modify
  members ["#{node['hopsworks']['user']}", "#{node['jupyter']['user']}"]
  append true
end

#update permissions of base_dir to 770
directory node['jupyter']['base_dir']  do
  owner node['jupyter']['user']  
  group node['jupyter']['group']
  mode "770"
  action :create
end

directory node['hopsworks']['dir']  do
  owner node['hopsworks']['user']
  group node['hopsworks']['group']
  mode "755"
  action :create
  not_if "test -d #{node['hopsworks']['dir']}"
end

directory domains_dir  do
  owner node['hopsworks']['user']
  group node['hopsworks']['group']
  mode "750"
  action :create
  not_if "test -d #{domains_dir}"
end


# For unzipping files

case node['platform_family']
when "debian"
  
  if node['platform_version'].to_f <= 14.04
    node.override['hopsworks']['systemd'] = "false"
  end
  package "dtrx"
  package "libkrb5-dev"

when "rhel"
  package "krb5-libs"
  
  remote_file "#{Chef::Config['file_cache_path']}/dtrx.tar.gz" do
    user node['glassfish']['user']
    group node['glassfish']['group']
    source "http://brettcsmith.org/2007/dtrx/dtrx-7.1.tar.gz"
    mode 0755
    action :create
  end

  bash "unpack_dtrx" do
    user "root"
    code <<-EOF
    set -e
    cd #{Chef::Config['file_cache_path']}
    tar -xzf dtrx.tar.gz
    cd dtrx-7.1
    python setup.py install --prefix=/usr/local
  EOF
    not_if "which dtrx"
  end
end







node.override = {
  'java' => {
    'install_flavor' => node['java']['install_flavor'],
    'jdk_version' => node['java']['jdk_version'],
    'oracle' => {
      'accept_oracle_download_terms' => true
    }
  },
  'glassfish' => {
    'version' => node['glassfish']['version'],
    'domains' => {
      domain_name => {
        'config' => {
          'systemd_enabled' => systemd,
          'systemd_start_timeout' => 240,
          'min_memory' => node['glassfish']['min_mem'],
          'max_memory' => node['glassfish']['max_mem'],
          'max_perm_size' => node['glassfish']['max_perm_size'],
          'max_stack_size' => node['glassfish']['max_stack_size'], 
          'port' => web_port,
          'admin_port' => admin_port,
          'username' => username,
          'password' => password,
          'master_password' => node['hopsworks']['master']['password'],
          'remote_access' => false,
          'secure' => false,
          'jvm_options' => ["-DHADOOP_HOME=#{node['hops']['dir']}/hadoop", "-DHADOOP_CONF_DIR=#{node['hops']['dir']}/hadoop/etc/hadoop", '-Dcom.sun.enterprise.tools.admingui.NO_NETWORK=true', '-Dlog4j.configuration=file:///${com.sun.aas.instanceRoot}/config/log4j.properties']
        },
        'extra_libraries' => {
          'jdbcdriver' => {
            'type' => 'common',
            'url' => node['hopsworks']['mysql_connector_url']
          }
        },
        'threadpools' => {
          'thread-pool-1' => {
            'maxthreadpoolsize' => 200,
            'minthreadpoolsize' => 5,
            'idletimeout' => 900,
            'maxqueuesize' => 4096
          },
          'http-thread-pool' => {
            'maxthreadpoolsize' => 200,
            'minthreadpoolsize' => 5,
            'idletimeout' => 900,
            'maxqueuesize' => 4096
          },
          'admin-pool' => {
            'maxthreadpoolsize' => 40,
            'minthreadpoolsize' => 5,
            'maxqueuesize' => 256
          }
        },
        'managed_thread_factories' => {
          'concurrent/hopsThreadFactory' => {
            'threadpriority' => 12,
            'description' => 'Hopsworks Thread Factory'
          }
        },
        'managed_executor_services' => {
          'concurrent/hopsExecutorService' => {
            'threadpriority' => 12,
            'description' => 'Hopsworks Executor Service'
          }
        },
        'managed_scheduled_executor_services' => {
          'concurrent/hopsScheduledExecutorService' => {
            'corepoolsize' => 12,
            'description' => 'Hopsworks Executor Service'
          }
        },
        'jdbc_connection_pools' => {
          'hopsworksPool' => {
            'config' => {
              'datasourceclassname' => 'com.mysql.jdbc.jdbc2.optional.MysqlDataSource',
              'restype' => 'javax.sql.DataSource',
              'isconnectvalidatereq' => 'true',
              'validationmethod' => 'auto-commit',
              'ping' => 'true',
              'description' => 'Hopsworks Connection Pool',
              'properties' => {
                'Url' => "jdbc:mysql://#{mysql_host}:3306/",
                'User' => mysql_user,
                'Password' => mysql_password
              }
            },
            'resources' => {
              'jdbc/hopsworks' => {
                'description' => 'Resource for Hopsworks Pool',
              }
            }
          },
          'ejbTimerPool' => {
            'config' => {
              'datasourceclassname' => 'com.mysql.jdbc.jdbc2.optional.MysqlDataSource',
              'restype' => 'javax.sql.DataSource',
              'isconnectvalidatereq' => 'true',

              'validationmethod' => 'auto-commit',
              'ping' => 'true',
              'description' => 'Hopsworks Connection Pool',
              'properties' => {
                'Url' => "jdbc:mysql://#{mysql_host}:3306/glassfish_timers",
                'User' => mysql_user,
                'Password' => mysql_password
              }
            },
            'resources' => {
              'jdbc/hopsworksTimers' => {
                'description' => 'Resource for Hopsworks EJB Timers Pool',
              }
            }
          }
        }
      }
    }
  }
}



installed = "#{node['glassfish']['base_dir']}/.installed"
if ::File.exists?( "#{installed}" ) == false

  package 'openssl'

  include_recipe 'glassfish::default'
  include_recipe 'glassfish::attribute_driven_domain'

  file "#{installed}" do # Mark that glassfish is installed
    owner node['glassfish']['user']
  end

  cauth = File.basename(node['hopsworks']['cauth_url'])

  remote_file "#{theDomain}/lib/#{cauth}"  do
    user node['glassfish']['user']
    group node['glassfish']['group']
    source node['hopsworks']['cauth_url']
    mode 0755
    action :create_if_missing
  end

end


# If the install.rb recipe failed and is re-run, install_dir needs to reset it
if node['glassfish']['install_dir'].include?("versions") == false
  node.override['glassfish']['install_dir'] = "#{node['glassfish']['install_dir']}/glassfish/versions/current"
end


template "#{theDomain}/docroot/404.html" do
  source "404.html.erb"
  owner node['glassfish']['user']
  mode 0777
  variables({
              :org_name => node['hopsworks']['org_name']
            })
  action :create
end

cookbook_file"#{theDomain}/docroot/obama-smoked-us.gif" do
  source 'obama-smoked-us.gif'
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0755'
  action :create
end


# if node['glassfish']['port'] == 80
#   authbind_port "AuthBind GlassFish Port 80" do
#     port 80
#     user node['glassfish']['user']
#   end
# end


case node['platform']
when "rhel"

  # Needed by sparkmagic
  package "krb5-libs"
  package "krb5-devel"

  service_name = "glassfish-#{domain_name}"
  file "/etc/systemd/system/#{service_name}.service" do
    owner "root"
    action :delete
  end

  template "/usr/lib/systemd/system/#{service_name}.service" do
    source 'systemd.service.erb'
    mode '0741'
    cookbook 'hopsworks'
    variables(
      :start_domain_command => "#{asadmin} start-domain #{password_file} --verbose false --debug false --upgrade false #{domain_name}",
      :restart_domain_command => "#{asadmin} restart-domain #{password_file} #{domain_name}",
      :stop_domain_command => "#{asadmin} stop-domain #{password_file} #{domain_name}",
      :authbind => requires_authbind,
      :listen_ports => [admin_port, node['glassfish']['port']])
  end

end


if systemd == true
  directory "/etc/systemd/system/glassfish-#{domain_name}.service.d" do
    owner "root"
    group "root"
    mode "755"
    action :create
  end

  template "/etc/systemd/system/glassfish-#{domain_name}.service.d/limits.conf" do
    source "limits.conf.erb"
    owner "root"
    mode 0774
    action :create
  end

  hopsworks_grants "reload_systemd" do
    tables_path  ""
    views_path ""
    rows_path  ""
    action :reload_systemd
  end

end

ca_dir = node['certs']['dir']

directory ca_dir do
  owner node['glassfish']['user']
  group node['kagent']['certs_group']
  mode "750"
  action :create
end

directory "#{ca_dir}/transient" do
  owner node['glassfish']['user']
  group node['kagent']['certs_group']
  mode "750"
  action :create
end

dirs = %w{certs crl newcerts private intermediate}

for d in dirs
  directory "#{ca_dir}/#{d}" do
    owner node['glassfish']['user']
    group node['glassfish']['group']
    mode "700"
    action :create
  end
end

int_dirs = %w{certs crl csr newcerts private}

for d in int_dirs
  directory "#{ca_dir}/intermediate/#{d}" do
    owner node['glassfish']['user']
    group node['glassfish']['group']
    mode "700"
    action :create
  end
end

template "#{ca_dir}/openssl-ca.cnf" do
  source "caopenssl.cnf.erb"
  owner node['glassfish']['user']
  mode "600"
  variables({
              :ca_dir =>  "#{ca_dir}"
            })
  action :create
end

template "#{ca_dir}/intermediate/openssl-intermediate.cnf" do
  source "intermediateopenssl.cnf.erb"
  owner node['glassfish']['user']
  mode "600"
  variables({
              :int_ca_dir =>  "#{ca_dir}/intermediate"
            })
  action :create
end

template "#{ca_dir}/intermediate/createusercerts.sh" do
  source "createusercerts.sh.erb"
  owner "root"
  group node['glassfish']['group']
  mode "510"
  variables({
              :int_ca_dir =>  "#{ca_dir}/intermediate/"
            })
  action :create
end

template "#{ca_dir}/intermediate/deleteusercerts.sh" do
  source "deleteusercerts.sh.erb"
  owner "root"
  group node['glassfish']['group']
  mode "510"
  variables({
              :int_ca_dir =>  "#{ca_dir}/intermediate/"
            })
  action :create
end

template "#{ca_dir}/intermediate/deleteprojectcerts.sh" do
  source "deleteprojectcerts.sh.erb"
  owner "root"
  group node['glassfish']['group']
  mode "510"
  variables({
              :int_ca_dir =>  "#{ca_dir}/intermediate/"
            })
  action :create
end

template "#{theDomain}/bin/ndb_backup.sh" do
  source "ndb_backup.sh.erb"
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode "754"
  action :create
end

template "#{theDomain}/bin/jupyter.sh" do
  source "jupyter.sh.erb"
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/jupyter-kernel-install.sh" do
  source "jupyter-kernel-install.sh.erb"
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode "550"
  action :create
end


template "#{theDomain}/bin/jupyter-project-cleanup.sh" do
  source "jupyter-project-cleanup.sh.erb"
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/jupyter-kill.sh" do
  source "jupyter-kill.sh.erb"
  owner node['glassfish']['user']
  group node['jupyter']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/jupyter-stop.sh" do
  source "jupyter-stop.sh.erb"
  owner node['glassfish']['user']
  group node['jupyter']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/jupyter-launch.sh" do
  source "jupyter-launch.sh.erb"
  owner node['glassfish']['user']
  group node['jupyter']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/unzip-hdfs-files.sh" do
  source "unzip-hdfs-files.sh.erb"
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/unzip-background.sh" do
  source "unzip-background.sh.erb"
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode "550"
  action :create
end

template "#{theDomain}/bin/global-ca-sign-csr.sh" do
  source "global-ca-sign-csr.sh.erb"
  owner node['glassfish']['user']
  mode 0550
  action :create
end

template "#{theDomain}/bin/ca-keystore.sh" do
  source "ca-keystore.sh.erb"
  owner node['glassfish']['user']
  mode 0550
  action :create
  variables({
         :directory => node["hopssite"]["keystore_dir"],
  })
end

template "/etc/sudoers.d/glassfish" do
  source "glassfish_sudoers.erb"
  owner "root"
  group "root"
  mode "0440"
  variables({
              :user => node['glassfish']['user'],
              :int_sh_dir =>  "#{ca_dir}/intermediate/createusercerts.sh",
              :delete_usercert =>  "#{ca_dir}/intermediate/deleteusercerts.sh",
              :delete_projectcert =>  "#{ca_dir}/intermediate/deleteprojectcerts.sh",
              :ndb_backup =>  "#{theDomain}/bin/ndb_backup.sh",
              :jupyter =>  "#{theDomain}/bin/jupyter.sh",
              :jupyter_cleanup =>  "#{theDomain}/bin/jupyter-project-cleanup.sh",
              :jupyter_kernel =>  "#{theDomain}/bin/jupyter-install-kernel.sh",
              :global_ca_sign =>  "#{theDomain}/bin/global-ca-sign-csr.sh",
              :ca_keystore => "#{theDomain}/bin/ca-keystore.sh"                            
            })
  action :create
end

# Replace sysv with our version. It increases the max number of open files limit (ulimit -n)
case node['platform']
when "ubuntu"
  file "/etc/init.d/glassfish-#{domain_name}" do
    owner "root"
    action :delete
  end

  template "/etc/init.d/glassfish-#{domain_name}" do
    source "glassfish.erb"
    owner "root"
    mode 0744
    action :create
    variables({
                :domain_name =>  domain_name,
                :password_file => password_file
              })

  end

end



#
# Jupyter Configuration
#


# Hopsworks user should own the directory so that hopsworks code
# can create the template files needed for Jupyter.
# Hopsworks will use a sudoer script to launch jupyter as the 'jupyter' user.
# The jupyter user will be able to read the files and write to the directories due to group permissions

user node["jupyter"]["user"] do
  home node["jupyter"]["base_dir"]
  gid node["jupyter"]["group"]  
  action :create
  shell "/bin/bash"
  manage_home true
  not_if "getent passwd #{node["jupyter"]["user"]}"
end

#update permissions of base_dir to 770
directory node["jupyter"]["base_dir"]  do
  owner node["jupyter"]["user"]  
  group node["jupyter"]["group"]
  mode "770"
  action :create
end

case node["platform_family"]
  when "debian"
   apt_package "python-openssl" do
     action :install
   end

  when "rhel"
   python_package "pyOpenSSL" do
     action :install
   end
end

#START hopssite install scripts
directory node['hopssite']['home'] do
  owner node['glassfish']['user']
  mode 0755
  action :create
end

template "#{node['hopssite']['home']}/hs_env.sh" do
  source "hopssite/hs_env.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_install.sh" do
  source "hopssite/hs_install.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_setup.sh" do
  source "hopssite/hs_setup.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_db_setup.sh" do
  source "hopssite/hs_db_setup.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_create_domain2.sh" do
  source "hopssite/hs_create_domain2.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_jdbc_connector.sh" do
  source "hopssite/hs_jdbc_connector.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_realm_setup.sh" do
  source "hopssite/hs_realm_setup.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_domain2_certs.sh" do
  source "hopssite/hs_domain2_certs.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_glassfish_sign.sh" do
  source "hopssite/hs_glassfish_sign.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_glassfish_certs.sh" do
  source "hopssite/hs_glassfish_certs.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_ssl_setup.sh" do
  source "hopssite/hs_ssl_setup.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_admin_certs.sh" do
  source "hopssite/hs_admin_certs.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_redeploy.sh" do
  source "hopssite/hs_redeploy.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_elastic.sh" do
  source "hopssite/hs_elastic.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_dela_certs.sh" do
  source "hopssite/hs_dela_certs.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_purge.sh" do
  source "hopssite/hs_purge.sh.erb" 
  owner node['glassfish']['user']
  group node['glassfish']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_tables.sql" do
  source "hopssite/hs_tables.sql.erb" 
  owner node['mysql']['user']
  group node['mysql']['group']
  action :create
  mode 0755
end

template "#{node['hopssite']['home']}/hs_rows.sql" do
  source "hopssite/hs_rows.sql.erb" 
  owner node['mysql']['user']
  group node['mysql']['group']
  action :create
  mode 0755
end
#END hopssite install scripts

directory node["hopssite"]["certs_dir"] do
  owner node["glassfish"]["user"]
  group node['kagent']['certs_group']
  mode "750"
  action :create
end

directory node["hopssite"]["keystore_dir"] do
  owner node["glassfish"]["user"]
  mode "750"
  action :create
end

template "#{theDomain}/config/ca.ini" do
  source "ca.ini.erb"
  owner node['glassfish']['user']
  mode 0750
  action :create
end

template "#{theDomain}/bin/csr-ca.py" do
  source "csr-ca.py.erb"
  owner node['glassfish']['user']
  mode 0750
  action :create
end

if node['hopssite']['manual_register'].empty? || node['hopssite']['manual_register'] == "false"
  hopsworks_certs "sign-ca-with-root-hopssite-ca" do
    action :sign_hopssite
  end
end
