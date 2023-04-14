#rows_path = "#{domains_dir}/post.sql"

case node['platform']
when "rhel"
  package "openssh-clients"
end

package "openssh-server"
public_ip=my_public_ip()
payara_config = "hopsworks-config"
config="server-config"
deployment_group = "hopsworks-dg"
local_instance = "instance0"
service_name="glassfish-instance"

domain_name= node['hopsworks']['domain_name']
domains_dir = node['glassfish']['domains_dir']
admin_port = node['hopsworks']['admin']['port']
username=node['hopsworks']['admin']['user']
password=node['hopsworks']['admin']['password']
ssh_nodes=private_recipe_ips('hopsworks', 'ssh_node')
config_nodes=private_recipe_ips('hopsworks', 'config_node')
current_version = node['hopsworks']['current_version']

asadmin = "#{node['glassfish']['base_dir']}/versions/current/bin/asadmin"
password_file = "#{domains_dir}/#{domain_name}_admin_passwd"

nodedir=node['glassfish']['nodes_dir']

asadmin_cmd="#{asadmin} -I false -t --user #{username} --passwordfile #{password_file}"

log_dir="#{nodedir}/#{node['hopsworks']['node_name']}/#{local_instance}/logs"

homedir = conda_helpers.get_user_home(node['hopsworks']['user'])
node.override['glassfish']['install_dir'] = "#{node['glassfish']['install_dir']}/glassfish/versions/current"
glassfish_user_home = conda_helpers.get_user_home(node['glassfish']['user'])

package "expect" do
  retries 10
  retry_delay 30
end

if node['hopsworks']['ha']['loadbalancer'].to_s == "true"
  # Install load balancer
  case node['platform_family']
  when "debian"
    package "apache2" do
      retries 10
      retry_delay 30
    end
    template "/etc/apache2/sites-available/loadbalancer.conf"  do
      source 'loadbalancer.conf.erb'
      user 'root'
      action :create
      variables({
        :load_balancer_port => "#{node['hopsworks']['ha']['loadbalancer_port']}",
        :load_balancer_log_dir => "/var/log/apache2",
        :public_ip => public_ip,
        :glassfish_nodes => ssh_nodes + config_nodes
      })
    end

    bash "configure load balancer" do
      user 'root'
      code <<-EOF
        sed -i 's/Listen 80$/Listen #{node['hopsworks']['ha']['loadbalancer_port']}/' /etc/apache2/ports.conf 
        a2enmod proxy_http
        a2enmod proxy_balancer lbmethod_byrequests
        a2dissite 000-default.conf
        a2ensite loadbalancer.conf
        systemctl restart apache2
      EOF
    end
  when "rhel"
    package ["httpd", "mod_ssl"] do
      retries 10
      retry_delay 30
    end
    directory "/etc/httpd/sites-available" do
      user 'root'
      action :create
      not_if { ::File.directory?('/etc/httpd/sites-available') }
    end
    directory "/etc/httpd/sites-enabled" do
      user 'root'
      action :create
      not_if { ::File.directory?('/etc/httpd/sites-enabled') }
    end

    template "/etc/httpd/sites-available/loadbalancer.conf"  do
      source 'loadbalancer.conf.erb'
      user 'root'
      action :create
      variables({
        :load_balancer_port => "#{node['hopsworks']['ha']['loadbalancer_port']}",
        :load_balancer_log_dir => "/var/log/httpd",
        :public_ip => public_ip,
        :glassfish_nodes => ssh_nodes + config_nodes
      })
    end

    bash "configure load balancer" do
      user 'root'
      code <<-EOF
        sed -i 's/Listen 80$/Listen #{node['hopsworks']['ha']['loadbalancer_port']}/' /etc/httpd/conf/httpd.conf
        echo 'IncludeOptional sites-enabled/*.conf' >> /etc/httpd/conf/httpd.conf
        ln -s /etc/httpd/sites-available/loadbalancer.conf /etc/httpd/sites-enabled/loadbalancer.conf
        systemctl restart httpd
      EOF
      not_if { ::File.exist?('/etc/httpd/sites-enabled/loadbalancer.conf') }
    end
  end
end

directory "#{nodedir}"  do
  owner node['hopsworks']['user']
  group node['hopsworks']['group']
  mode "750"
  action :create
  not_if "test -d #{nodedir}"
end

# Create a configuration b/c server-config can not be used for HA
glassfish_asadmin "copy-config default-config #{payara_config}" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  not_if "#{asadmin_cmd} list-configs | grep #{payara_config}"
end

jvm_options = [
  "-XX:MaxPermSize=#{node['glassfish']['max_perm_size']}m", 
  "-Xss#{node['glassfish']['max_stack_size']}k", 
  "-Xms#{node['glassfish']['min_mem']}m", 
  "-Xmx#{node['glassfish']['max_mem']}m", 
  "-DHADOOP_HOME=#{node['hops']['dir']}/hadoop", 
  "-DHADOOP_CONF_DIR=#{node['hops']['dir']}/hadoop/etc/hadoop"]

glassfish_jvm_options "JvmOptions #{payara_config}" do
  domain_name domain_name
  admin_port admin_port
  username username
  password_file password_file
  secure false
  options jvm_options
end

hopsworks_configure_server "glassfish_configure_realm" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  target payara_config
  asadmin asadmin
  action :glassfish_configure_realm
end

hopsworks_configure_server "glassfish_configure_network" do
  domain_name domain_name
  domains_dir domains_dir
  password_file password_file
  username username
  admin_port admin_port
  target payara_config
  asadmin asadmin
  internal_port node['hopsworks']['internal']['port']
  network_name "https-internal"
  action :glassfish_configure_network
end

if node['hopsworks']['ha']['loadbalancer'].to_s == "true"
  # http internal for load balancer
  hopsworks_configure_server "glassfish_configure_network" do
    domain_name domain_name
    domains_dir domains_dir
    password_file password_file
    username username
    admin_port admin_port
    target payara_config
    asadmin asadmin
    internal_port 28182
    network_name "http-internal"
    securityenabled false
    action :glassfish_configure_network
  end
end

# disable monitoring and http-listeners on server-config
glassfish_network_listener_conf = {
  "configs.config.#{config}.network-config.network-listeners.network-listener.http-listener-2.enabled" => false,
  "configs.config.#{config}.network-config.network-listeners.network-listener.https-int-list.enabled" => false,
  "configs.config.#{config}.rest-monitoring-configuration.enabled" => false,
  "configs.config.#{config}.monitoring-service.mbean-enabled" => false,
  "configs.config.#{config}.monitoring-service.monitoring-enabled" => false,
  "configs.config.#{config}.microprofile-metrics-configuration.enabled" => false
}

hopsworks_configure_server "glassfish_configure" do
  domain_name domain_name
  domains_dir domains_dir
  password_file password_file
  username username
  admin_port admin_port
  target payara_config
  asadmin asadmin
  override_props glassfish_network_listener_conf
  action :glassfish_configure
end

hopsworks_configure_server "glassfish_configure_monitoring" do
  domain_name domain_name
  domains_dir domains_dir
  password_file password_file
  username username
  admin_port admin_port
  target payara_config
  asadmin asadmin
  action :glassfish_configure_monitoring
end

# 192.168.91.101.rpartition(".") = ["192.168.91", ".", "101"]
interfaces = public_ip.rpartition(".")[0]
glassfish_asadmin "set-hazelcast-configuration --publicaddress #{public_ip} --daspublicaddress #{public_ip} --autoincrementport true --interfaces #{interfaces}.* --membergroup #{payara_config} --target #{payara_config}" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
end

glassfish_asadmin "create-local-instance --config #{payara_config} --nodedir #{nodedir} #{local_instance}" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  not_if "#{asadmin_cmd} list-instances | grep #{local_instance}"
end

directory node['hopsworks']['data_volume']['localhost-domain1'] do
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0750'
end

directory node['hopsworks']['data_volume']['node_logs'] do
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0750'
end

bash 'Move glassfish logs to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{log_dir}/* #{node['hopsworks']['data_volume']['node_logs']}
    mv -f #{log_dir} #{node['hopsworks']['data_volume']['node_logs']}_deprecated
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(log_dir)}
  not_if { File.symlink?(log_dir)}
end

link "#{log_dir}" do
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0750'
  to node['hopsworks']['data_volume']['node_logs']
end

glassfish_asadmin "create-system-properties --target #{local_instance} hazelcast.local.publicAddress=#{public_ip}" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  not_if "#{asadmin_cmd} list-system-properties #{local_instance} | grep hazelcast.local.publicAddress=#{public_ip}"
end

#
# mod_ajp http://www.devwithimagination.com/2015/08/13/apache-as-a-reverse-proxy-to-glassfish/
#
# https://dzone.com/articles/configure-a-glassfish-cluster-with-automatic-load
# docker
# https://github.com/jelastic-jps/glassfish/
# --nodedir #{domains_dir}/nodes will fail to start and need restarting from the node

# This will not work when adding nodes on upgrade
ssh_nodes.each_with_index do |val, i|
  index = i + 1
  glassfish_asadmin "create-node-ssh --nodehost #{val} --installdir #{node['glassfish']['base_dir']}/versions/current --nodedir #{nodedir} --sshkeyfile #{glassfish_user_home}/.ssh/id_ed25519 worker#{index}" do
    domain_name domain_name
    password_file password_file
    username username
    admin_port admin_port
    secure false
    not_if "#{asadmin_cmd} list-nodes | grep worker#{index}"
  end
  glassfish_asadmin "create-instance --config #{payara_config} --node worker#{index} instance#{index}" do
    domain_name domain_name
    password_file password_file
    username username
    admin_port admin_port
    secure false
    not_if "#{asadmin_cmd} list-instances | grep instance#{index}"
  end

  glassfish_asadmin "create-system-properties --target instance#{index} hazelcast.local.publicAddress=#{val}" do
    domain_name domain_name
    password_file password_file
    username username
    admin_port admin_port
    secure false
    not_if "#{asadmin_cmd} list-system-properties instance#{index} | grep hazelcast.local.publicAddress=#{val}"
  end
end

# This is done here to reserve the name of the worker
config_nodes.each_with_index do |val, i|
  index = i + 1 + ssh_nodes.length()
  glassfish_asadmin "create-node-config --nodehost #{val} --installdir #{node['glassfish']['base_dir']}/versions/current --nodedir #{nodedir} worker#{index}" do
    domain_name domain_name
    password_file password_file
    username username
    admin_port admin_port
    secure false
    not_if "#{asadmin_cmd} list-nodes | grep worker#{index}"
  end
end

glassfish_asadmin "create-deployment-group #{deployment_group}" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  not_if "#{asadmin_cmd} list-deployment-groups | grep #{deployment_group}"
end

glassfish_asadmin "add-instance-to-deployment-group --instance #{local_instance} --deploymentgroup #{deployment_group}" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
end

ssh_nodes.each_with_index do |val, index|
  glassfish_asadmin "add-instance-to-deployment-group --instance instance#{index + 1} --deploymentgroup #{deployment_group}" do
    domain_name domain_name
    password_file password_file
    username username
    admin_port admin_port
    secure false
  end
end

glassfish_deployable "hopsworks-ear" do
  component_name "hopsworks-ear:#{node['hopsworks']['version']}"
  target config
  version current_version
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  action :undeploy
  retries 1
  keep_state true
  enabled true
  secure true
  ignore_failure true
  only_if "#{asadmin_cmd} list-applications --type ejb #{config} | grep -w \"hopsworks-ear:#{node['hopsworks']['version']}\""
end

glassfish_deployable "hopsworks" do
  component_name "hopsworks-web:#{node['hopsworks']['version']}"
  target config
  version current_version
  context_root "/hopsworks"
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure true
  action :undeploy
  async_replication false
  retries 1
  keep_state true
  enabled true
  ignore_failure true 
  only_if "#{asadmin_cmd} list-applications --type web #{config} | grep -w \"hopsworks-web:#{node['hopsworks']['version']}\"" 
end

glassfish_deployable "hopsworks-ca" do
  component_name "hopsworks-ca:#{node['hopsworks']['version']}"
  target config
  version current_version
  context_root "/hopsworks-ca"
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure true
  action :undeploy
  async_replication false
  retries 1
  keep_state true
  enabled true
  ignore_failure true
  only_if "#{asadmin_cmd} list-applications --type ejb #{config} | grep -w \"hopsworks-ca:#{node['hopsworks']['version']}\""
end

hopsworks_configure_server "change_node_master_password" do
  username username
  asadmin asadmin
  nodedir nodedir
  node_name node['hopsworks']['node_name']
  current_master_password "changeit"
  action :change_node_master_password
end

# Resources created in default server, so create a reference to the resources in the new config
glassfish_resources = [
  'concurrent/hopsThreadFactory',
  'concurrent/condaExecutorService',
  'concurrent/hopsExecutorService',
  'concurrent/jupyterExecutorService',
  'concurrent/condaScheduledExecutorService',
  'concurrent/hopsScheduledExecutorService',
  'concurrent/kagentExecutorService',
  'jdbc/airflow', 
  'jdbc/featurestore', 
  'jdbc/hopsworks', 
  'jdbc/hopsworksTimers',
  'ldap/LdapResource',
  'mail/BBCMail']

glassfish_resources.each do |val|
  glassfish_asadmin "create-resource-ref --target #{deployment_group} #{val}" do
    domain_name domain_name
    password_file password_file
    username username
    admin_port admin_port
    secure false
    only_if "#{asadmin_cmd} list-resource-refs #{config} | grep #{val}"
    not_if "#{asadmin_cmd} list-resource-refs #{deployment_group} | grep #{val}"
  end
end

#restart only if new (no deployed apps)
glassfish_asadmin "restart-domain" do
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  not_if "#{asadmin_cmd} list-applications #{deployment_group} | grep -w \"hopsworks-ca:#{node['hopsworks']['version']}\""
  only_if "#{asadmin_cmd} list-instances #{deployment_group} | grep -w \"not running\""
end

kagent_config "glassfish-#{domain_name}" do
  service "glassfish_#{domain_name}"
  role service_name
  log_file "#{nodedir}/#{node['hopsworks']['node_name']}/#{local_instance}/logs/server.log"
  restart_agent true
  only_if {node['kagent']['enabled'].casecmp? "true"}
  only_if { ::File.directory?("#{nodedir}")}
  not_if "systemctl is-active --quiet #{service_name}"
end

hopsworks_worker "add_to_services" do
  asadmin asadmin
  admin_port admin_port
  username username
  password_file password_file
  nodedir nodedir
  service_name service_name
  action :add_to_services
  not_if "systemctl is-active --quiet #{service_name}"
end

if current_version.eql?("") == false
  #
  # undeploy previous version
  #
  glassfish_deployable "hopsworks-ear" do
    component_name "hopsworks-ear:#{node['hopsworks']['current_version']}"
    target deployment_group
    version current_version
    domain_name domain_name
    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
    username username
    admin_port admin_port
    action :undeploy
    retries 1
    keep_state true
    enabled true
    secure true
    ignore_failure true
  end

  glassfish_deployable "hopsworks" do
    component_name "hopsworks-web:#{node['hopsworks']['current_version']}"
    target deployment_group
    version current_version
    context_root "/hopsworks"
    domain_name domain_name
    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
    username username
    admin_port admin_port
    secure true
    action :undeploy
    async_replication false
    retries 1
    keep_state true
    enabled true
    ignore_failure true  
  end

  glassfish_deployable "hopsworks-ca" do
    component_name "hopsworks-ca:#{node['hopsworks']['current_version']}"
    target deployment_group
    version current_version
    context_root "/hopsworks-ca"
    domain_name domain_name
    password_file "#{domains_dir}/#{domain_name}_admin_passwd"
    username username
    admin_port admin_port
    secure true
    action :undeploy
    async_replication false
    retries 1
    keep_state true
    enabled true
    ignore_failure true
  end
end    

# change reference of the deployed apps will require restarting instances
glassfish_deployable "hopsworks-ca" do
  component_name "hopsworks-ca:#{node['hopsworks']['version']}"
  target deployment_group
  url node['hopsworks']['ca_url']
  auth_username node['install']['enterprise']['username']
  auth_password node['install']['enterprise']['password']
  version node['hopsworks']['version']
  context_root "/hopsworks-ca"
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  action :deploy
  async_replication false
  retries 1
  keep_state true
  enabled true
  not_if "#{asadmin_cmd} list-applications --type ejb #{deployment_group} | grep -w \"hopsworks-ca:#{node['hopsworks']['version']}\""
end

glassfish_deployable "hopsworks-ear" do
  component_name "hopsworks-ear:#{node['hopsworks']['version']}"
  target deployment_group
  url node['hopsworks']['ear_url']
  auth_username node['install']['enterprise']['username']
  auth_password node['install']['enterprise']['password']
  version node['hopsworks']['version']
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  action :deploy
  async_replication false
  retries 1
  keep_state true
  enabled true
  not_if "#{asadmin_cmd} list-applications --type ejb #{deployment_group} | grep -w \"hopsworks-ear:#{node['hopsworks']['version']}\""
end

glassfish_deployable "hopsworks" do
  component_name "hopsworks-web:#{node['hopsworks']['version']}"
  target deployment_group
  url node['hopsworks']['war_url']
  auth_username node['install']['enterprise']['username']
  auth_password node['install']['enterprise']['password']
  version node['hopsworks']['version']
  context_root "/hopsworks"
  domain_name domain_name
  password_file password_file
  username username
  admin_port admin_port
  secure false
  action :deploy
  async_replication false
  retries 1
  keep_state true
  enabled true
  not_if "#{asadmin_cmd} list-applications --type web #{deployment_group} | grep -w \"hopsworks-web:#{node['hopsworks']['version']}\""
end
