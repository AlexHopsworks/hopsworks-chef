
domain_name= node['hopsworks']['domain_name']
domains_dir = node['glassfish']['domains_dir']
asadmin = "#{node['glassfish']['base_dir']}/versions/current/bin/asadmin"
password_file = "#{domains_dir}/#{domain_name}_admin_passwd"
username=node['hopsworks']['admin']['user']
nodedir=node['glassfish']['nodes_dir']

admin_port = node['hopsworks']['admin']['port']
master_ip=private_recipe_ip('hopsworks', 'master')
public_ip=my_public_ip()

asadmin_cmd="#{asadmin} --host #{master_ip} --port #{admin_port} --user #{username} --passwordfile #{password_file}"
service_name="glassfish-instance"

node_name=get_node_name(asadmin_cmd, public_ip)
instance_name=get_instance_name(asadmin_cmd, node_name)

log_dir="#{nodedir}/#{node_name}/#{instance_name}/logs"
data_volume_logs_dir="#{node['hopsworks']['data_volume']['root_dir']}/#{node_name}/logs"

directory "#{node['hopsworks']['data_volume']['root_dir']}/#{node_name}" do
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0750'
end

directory "#{data_volume_logs_dir}" do
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0750'
end

bash 'Move glassfish logs to data volume' do
  user 'root'
  code <<-EOH
    set -e
    mv -f #{log_dir}/* #{data_volume_logs_dir}
    mv -f #{log_dir} #{data_volume_logs_dir}_deprecated
  EOH
  only_if { conda_helpers.is_upgrade }
  only_if { File.directory?(log_dir)}
  not_if { File.symlink?(log_dir)}
end

link "#{log_dir}" do
  owner node['glassfish']['user']
  group node['glassfish']['group']
  mode '0750'
  to data_volume_logs_dir
end

bash "create_users_groups_view" do
  user "root"
  code <<-EOH
    #{node['ndb']['scripts_dir']}/mysql-client.sh --database=hopsworks -e \"CREATE OR REPLACE ALGORITHM=UNDEFINED VIEW users_groups AS select u.username AS username,u.password AS password,u.secret AS secret,u.email AS email,g.group_name AS group_name from ((user_group ug join users u on((u.uid = ug.uid))) join bbc_group g on((g.gid = ug.gid)));\" 
  EOH
end

# Register Glassfish with Consul
template "#{node['glassfish']['domains_dir']}/#{node['hopsworks']['domain_name']}/bin/glassfish-health.sh" do
  source "consul/glassfish-health.sh.erb"
  owner node['hopsworks']['user']
  group node['hops']['group']
  mode 0750
end

consul_service "Registering Glassfish worker with Consul" do
  service_definition "consul/glassfish-worker-consul.hcl.erb"
  reload_consul false
  action :register
end

# We can't use the internal port yet as the certificate has not been generated yet
hopsworks_certs "generate-int-certs" do
  subject     "/CN=#{node['hopsworks']['hopsworks_public_host']}/OU=0"
  action      :generate_int_certs
end

hopsworks_certs "import-user-certs" do
  action :import_certs
  not_if { node['hopsworks']['https']['key_url'].eql?("") }
end

hopsworks_alt_url = "https://#{private_recipe_ip("hopsworks","default")}:#{node["hopsworks"]["internal"]["port"]}"
kagent_hopsify "Generate x.509" do
  user node['hopsworks']['user']
  crypto_directory x509_helper.get_crypto_dir(node['hopsworks']['user'])
  hopsworks_alt_url hopsworks_alt_url
  common_name node['hopsworks']['hopsworks_public_host']
  action :generate_x509
end

#we do not want glassfish DAS on worker 
service "glassfish-#{domain_name}" do
  provider Chef::Provider::Service::Systemd
  supports :restart => true, :stop => true, :start => true, :status => true, :disable => true
  action :stop
end
service "glassfish-#{domain_name}" do
  provider Chef::Provider::Service::Systemd
  supports :restart => true, :stop => true, :start => true, :status => true, :disable => true
  action :disable
end

hopsworks_configure_server "change_node_master_password" do
  username username
  asadmin asadmin
  admin_pwd admin_pwd
  nodedir nodedir
  node_name node_name
  current_master_password "changeit"
  action :change_node_master_password
end

kagent_config "glassfish-#{domain_name}" do
  service "glassfish_#{domain_name}"
  role service_name
  log_file "#{nodedir}/#{node_name}/#{instance_name}/logs/server.log"
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
