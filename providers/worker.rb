action :add_to_services do
  asadmin=new_resource.asadmin
  admin_port=new_resource.admin_port
  username=new_resource.username
  password_file=new_resource.password_file
  nodedir=new_resource.nodedir
  service_name=new_resource.service_name
  systemd_start_timeout=new_resource.systemd_start_timeout
  systemd_stop_timeout=new_resource.systemd_stop_timeout

  start_instance_command = "#{asadmin} --user #{username} --passwordfile #{password_file} start-local-instance --sync normal --nodedir #{nodedir}"
  restart_instance_command = "#{asadmin} --user #{username} --passwordfile #{password_file} restart-local-instance --nodedir #{nodedir}"
  stop_instance_command = "#{asadmin} --user #{username} --passwordfile #{password_file} stop-local-instance --nodedir #{nodedir}"

  #we hard code systemd enabled in install.rb
  template "/lib/systemd/system/#{service_name}.service" do
    source 'systemd.service.erb'
    mode '0644'
    cookbook 'hopsworks'

    variables(start_domain_command: "#{start_instance_command}",
              restart_domain_command: "#{restart_instance_command}",
              stop_domain_command: "#{stop_instance_command}",
              start_domain_timeout: systemd_start_timeout,
              stop_domain_timeout: systemd_stop_timeout)
    notifies :start, "service[#{service_name}]", :delayed
  end

  service service_name do
    supports start: true, restart: true, stop: true, status: true
    action [:enable]
  end
end