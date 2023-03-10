actions :add_to_services

attribute :asadmin, :kind_of => String, :default => nil
attribute :password_file, :kind_of => String, :default => nil
attribute :username, :kind_of => String, :default => nil
attribute :admin_port, :kind_of => Integer, :default => 4848
attribute :nodedir, :kind_of => String, :default => nil
attribute :service_name, :kind_of => String, :default => nil
attribute :systemd_start_timeout, :kind_of => Integer, :default => 900
attribute :systemd_stop_timeout, :kind_of => Integer, :default => 90

default_action :add_to_services