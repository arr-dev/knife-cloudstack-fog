# Author:: Jeff Moody (<jmoody@datapipe.com>), Takashi Kanai (<anikundesu@gmail.com>)
# Copyright:: Copyright (c) 2012 Datapipe,  Copyright (c) 2012 IDC Frontier Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife/bootstrap'
Chef::Knife::Bootstrap.load_deps
require 'socket'
require 'net/ssh/multi'
require 'chef/json_compat'
require 'chef/knife/cloudstack_base'
require 'chef/knife/ssh'
Chef::Knife::Ssh.load_deps

class Chef
	class Knife
		class CloudstackServerCreate < Knife

			include Knife::CloudstackBase

			banner "knife cloudstack server create -s SERVICEID -t TEMPLATEID -z ZONEID (options)"

			option  :cloudstack_serviceid,
						:short => "-s SERVICEID",
						:long => "--serviceid SERVICEID",
						:description => "The CloudStack service offering ID."

			option  :cloudstack_templateid,
						:short => "-t TEMPLATEID",
						:long => "--templateid TEMPLATEID",
						:description => "The CloudStack template ID for the server."

			option  :cloudstack_zoneid,
						:short => "-z ZONEID",
						:long => "--zoneid ZONE",
						:description => "The CloudStack zone ID for the server."

			option  :cloudstack_networkids,
						:short => "-w NETWORKIDS",
						:long => "--networkids NETWORKIDS",
						:description => "Comma separated list of CloudStack network IDs.",
						:proc => lambda { |n| n.split(/[\s,]+/) },
						:default => []

			option  :cloudstack_groupids,
						:short => "-g SECURITYGROUPIDS",
						:long => "--groupids SECURITYGROUPIDS",
						:description => "Comma separated list of CloudStack Security Group IDs.",
						:proc => lambda { |n| n.split(/[\s,]+/) },
						:default => []

			option  :cloudstack_groupnames,
						:short => "-G SECURITYGROUPNAMES",
						:long => "--groupnames SECURITYGROUPNAMES",
						:description => "Comma separated list of CloudStack Security Group names. Each group name must be encapuslated in quotes if it contains whitespace.",
						:proc => lambda { |n| n.split(/[\s,]+/) },
						:default => []

			option  :distro,
						:short => "-d DISTRO",
						:long => "--distro DISTRO",
						:description => "Bootstrap a distro using a template; default is 'chef-full'",
						:proc => Proc.new { |d| Chef::Config[:knife][:distro] = d },
						:default => "chef-full"

			option  :template_file,
						:long => "--template-file TEMPLATE",
						:description => "Full path to location of template to use",
						:proc => Proc.new { |t| Chef::Config[:knife][:template_file] = t },
						:default => false

			option  :run_list,
						:short => "-r RUN_LIST",
						:long => "--run-list RUN_LIST",
						:description => "Comma separated list of roles/recipes to apply",
						:proc => lambda { |o| o.split(/[\s,]+/) },
						:default => []

			option  :ssh_user,
						:short => "-x USERNAME",
						:long => "--ssh-user USERNAME",
						:description => "The ssh username",
						:default => 'root'

			option  :ssh_password,
						:short => "-P PASSWORD",
						:long => "--ssh-password PASSWORD",
						:description => "The ssh password"

			option  :identity_file,
						:short => "-i PRIVATE_KEY_FILE",
						:long => "--identity-file PRIVATE_KEY_FILE",
						:description => "The Private key file for authenticating SSH session. --keypair option is also needed."

			option 	:ssh_port,
						:short => "-p PORT",
						:long => "--ssh-port PORT",
						:description => "The port which SSH should be listening on. If unspecified, will default to 22."

			option  :server_display_name,
						:short => "-N NAME",
						:long => "--display-name NAME",
						:description => "The instance display name"

			option  :host_name,
						:short => "-H NAME",
						:long => "--hostname NAME",
						:description => "The instance host name"

			option  :keypair,
						:short => "-k KEYPAIR",
						:long => "--keypair KEYPAIR",
						:description => "The CloudStack Key Pair to use for SSH key authentication."

			option  :diskoffering,
						:short => "-D DISKOFFERINGID",
						:long => "--diskoffering DISKOFFERINGID",
						:description => "Specifies either the Disk Offering ID for the ROOT disk for an ISO template, or a DATA disk."

			option  :size,
						:short => "-Z SIZE",
						:long => "--size SIZE",
						:description => "Specifies the arbitrary Disk Size for DATADISK volume in GB. Must be passed with custom size Disk Offering ID."

			option 	:random_ssh_port,
						:long => "--random-ssh-port",
						:description => "Map a random, unused high-level port to 22 for SSH and creates a port forward for this mapping. For Isolated Networking and VPC only."

			option 	:ssh_gateway,
						:short => "-W GATEWAY",
						:long => "--ssh-gateway GATEWAY",
						:description => "The ssh gateway server. Connection is defined as USERNAME@HOST:PORT",
						:proc => Proc.new { |key| Chef::Config[:knife][:ssh_gateway] = key }

			# def bootstrap_for_node(host, user, password)
			def bootstrap_for_node(server, ssh_host)
				host = server["name"]
				user = config[:ssh_user]
				password = server["password"]
				Chef::Log.debug("Bootstrap host: #{host}")
				Chef::Log.debug("Bootstrap user: #{user}")
				Chef::Log.debug("Bootstrap pass: #{password}")
				bootstrap = Chef::Knife::Bootstrap.new
				bootstrap.name_args = [ssh_host]
				bootstrap.config[:run_list] = config[:run_list]
				bootstrap.config[:ssh_user] = user
				bootstrap.config[:ssh_password] = password
				bootstrap.config[:ssh_gateway] = config[:ssh_gateway]
				bootstrap.config[:identity_file] = locate_config_value(:identity_file)
				bootstrap.config[:chef_node_name] = config[:server_display_name] if config[:server_display_name]
				bootstrap.config[:prerelease] = config[:prerelease]
				bootstrap.config[:bootstrap_version] = locate_config_value(:bootstrap_version)
				bootstrap.config[:distro] = locate_config_value(:distro)
				bootstrap.config[:use_sudo] = true
				bootstrap.config[:template_file] = locate_config_value(:template_file)
				bootstrap.config[:environment] = config[:environment]
				# may be needed for vpc_mode
				bootstrap.config[:no_host_key_verify] = config[:no_host_key_verify]
				begin
					bootstrap
				rescue
					sleep @initial_sleep_delay
					retry
				end
			end

			def check_port_available(public_port, ipaddressid)
				Chef::Log.debug("Checking if port #{public_port} is available.")
				pubport = public_port.to_i
				port_forward_rules_query = connection.list_port_forwarding_rules({'ipaddressid' => ipaddressid })
				port_rules = port_forward_rules_query['listportforwardingrulesresponse']['portforwardingrule']
				is_available = true
				some_possible_rules = port_rules.select { |rule| rule['publicport'].to_i <= pubport }
				possible_rules = some_possible_rules.select { |rule| rule['publicendport'].to_i >= pubport }
				possible_rules.each do |rule|
					startport = rule['publicport'].to_i
					endport = rule['publicendport'].to_i
					Chef::Log.debug("Determining if #{pubport} is between #{startport} and #{endport}.")
					if (endport != startport)
						if pubport.between?(startport, endport)
							is_available = false
						else
							is_available = true
						end
					else
						if (pubport == startport)
							is_available = false
						else
							is_available = true
						end
					end
				end
				return is_available
			end

			def add_port_forward(public_start_port, public_end_port, server_id, ipaddressid, privateport)
				pfwdops = {}
				pfwdops['ipaddressid'] = ipaddressid
				pfwdops['privateport'] = privateport
				pfwdops['protocol'] = "TCP"
				pfwdops['virtualmachineid'] = server_id
				pfwdops['openfirewall'] = "true"
				pfwdops['publicport'] = public_start_port
				pfwdops['publicendport'] = public_end_port
				rule_create_job = connection.create_port_forwarding_rule(pfwdops)
				print "#{ui.color("Creating port forwarding rule.", :cyan)}"
				while (@connection.query_async_job_result({'jobid' => rule_create_job['createportforwardingruleresponse']['jobid']})['queryasyncjobresultresponse'].fetch('jobstatus') == 0)
					print("#{ui.color(".", :cyan)}")
					sleep 2
				end
				print("\n")
			end

			def create_server_def
				server_def = {
					"templateid" => locate_config_value(:cloudstack_templateid),
					"serviceofferingid" => locate_config_value(:cloudstack_serviceid),
					"zoneid" => locate_config_value(:cloudstack_zoneid)
				}

				if locate_config_value(:server_display_name) != nil
					server_def["displayname"] = locate_config_value(:server_display_name)
				end

				if locate_config_value(:host_name) != nil
					server_def["name"] = locate_config_value(:host_name)
				end

				network_ids = []
				if locate_config_value(:cloudstack_networkids) != []
					cs_networkids = locate_config_value(:cloudstack_networkids)
					cs_networkids.each do |id|
						network_ids.push(id)
					end
					server_def["networkids"] = network_ids
				end

				security_groups = []
				if locate_config_value(:cloudstack_groupids) != []
					cs_groupids = locate_config_value(:cloudstack_groupids)
					cs_groupids.each do |id|
						security_groups.push(id)
					end
					server_def["securitygroupids"] = security_groups
				elsif locate_config_value(:cloudstack_groupnames) != []
					cs_groupnames = locate_config_value(:cloudstack_groupnames)
					cs_groupnames.each do |name|
						security_groups.push(name)
					end
					server_def["securitygroupnames"] = security_groups
				end

				if locate_config_value(:keypair) != nil
					server_def["keypair"] = locate_config_value(:keypair)
				end

				if locate_config_value(:diskoffering) != nil
					server_def["diskofferingid"] = locate_config_value(:diskoffering)
				end

				if locate_config_value(:size) != nil
					server_def["size"] = locate_config_value(:size)
				end

				server_def
			end

			def knife_ssh
				ssh = Chef::Knife::Ssh.new
				ssh.ui = ui
				ssh.name_args = [ @primary_ip, ssh_command ]
				ssh.config[:ssh_user] = Chef::Config[:knife][:ssh_user] || config[:ssh_user]
				ssh.config[:ssh_password] = config[:ssh_password]
				ssh.config[:ssh_port] = Chef::Config[:knife][:ssh_port] || config[:ssh_port]
				ssh.config[:ssh_gateway] = Chef::Config[:knife][:ssh_gateway] || config[:ssh_gateway]
				ssh.config[:forward_agent] = Chef::Config[:knife][:forward_agent] || config[:forward_agent]
				ssh.config[:identity_file] = Chef::Config[:knife][:identity_file] || config[:identity_file]
				ssh.config[:manual] = true
				ssh.config[:host_key_verify] = Chef::Config[:knife][:host_key_verify] || config[:host_key_verify]
				ssh.config[:on_error] = :raise
				ssh
			end

			def find_template(template=nil)
				# Are we bootstrapping using an already shipped template?
				if config[:template_file]
					bootstrap_files = config[:template_file]
				else
					bootstrap_files = []
					bootstrap_files << File.join(File.dirname(__FILE__), 'bootstrap', "#{config[:distro]}.erb")
					bootstrap_files << File.join(Knife.chef_config_dir, "bootstrap", "#{config[:distro]}.erb") if Knife.chef_config_dir
					bootstrap_files << File.join(ENV['HOME'], '.chef', 'bootstrap', "#{config[:distro]}.erb") if ENV['HOME']
					bootstrap_files << Gem.find_files(File.join("chef","knife","bootstrap","#{config[:distro]}.erb"))
					bootstrap_files.flatten!
				end

				template = Array(bootstrap_files).find do |bootstrap_template|
					Chef::Log.debug("Looking for bootstrap template in #{File.dirname(bootstrap_template)}")
					File.exists?(bootstrap_template)
				end

				unless template
					ui.info("Can not find bootstrap definition for #{config[:distro]}")
					raise Errno::ENOENT
				end

				Chef::Log.debug("Found bootstrap template in #{File.dirname(template)}")

				template
			end

			def render_template(template=nil)
				context = Knife::Core::BootstrapContext.new(config, config[:run_list], Chef::Config)
				Erubis::Eruby.new(template).evaluate(context)
			end

			def read_template
				IO.read(@template_file).chomp
			end

			def knife_ssh_with_password_auth
				ssh = knife_ssh
				ssh.config[:identity_file] = nil
				ssh.config[:ssh_password] = ssh.get_password
				ssh
			end

			def ssh_command
				command = render_template(read_template)

				if config[:use_sudo]
					command = config[:use_sudo_password] ? "echo #{config[:ssh_password]} | sudo -S #{command}" : "sudo #{command}"
				end

				command
			end

			def run
				$stdout.sync = true
				options = create_server_def
				Chef::Log.debug("Options: #{options} \n")

				@initial_sleep_delay = 10				
				@sshport = 22

				config[:host_key_verify] = false

				if locate_config_value(:ssh_port) != nil
					@sshport = locate_config_value(:ssh_port).to_i
				end

				serverdeploy = connection.deploy_virtual_machine(options)
				jobid = serverdeploy['deployvirtualmachineresponse'].fetch('jobid')

				server_start = connection.query_async_job_result('jobid'=>jobid)

				Chef::Log.debug("Job ID: #{jobid} \n")

				print "#{ui.color("Waiting for server", :magenta)}"
				while server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 0
					print "#{ui.color(".", :magenta)}"
					sleep @initial_sleep_delay
					server_start = connection.query_async_job_result('jobid'=>jobid)
					Chef::Log.debug("Server_Start: #{server_start} \n")
				end
				puts "\n\n"

				if server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 2
					errortext = server_start['queryasyncjobresultresponse'].fetch('jobresult').fetch('errortext')
					puts "#{ui.color("ERROR! Job failed with #{errortext}", :red)}"
				end

				if server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 1

					Chef::Log.debug("Job ID: #{jobid} \n")
					Chef::Log.debug("Options: #{options} \n")
					server_start = connection.query_async_job_result('jobid'=>jobid)
					Chef::Log.debug("Server_Start: #{server_start} \n")

					@server = server_start['queryasyncjobresultresponse']['jobresult']['virtualmachine']

					server_display_name = @server['displayname']
					server_id = @server['name']
					server_serviceoffering = @server['serviceofferingname']
					server_template = @server['templatename']
					if @server['password'] != nil
						config[:ssh_password] = @server['password']
					else
						config[:ssh_password] = locate_config_value(:ssh_password)
					end

					ssh_user = locate_config_value(:ssh_user)

					@primary_ip = nil

					if @server['nic'].size > 0
						@primary_ip = @server['nic'].first['ipaddress']
					end

					if locate_config_value(:random_ssh_port) != nil
						public_ips = connection.list_public_ip_addresses("associatednetworkid" => @server['nic'][0]['networkid'])
						primary_public_ip_id = public_ips['listpublicipaddressesresponse']['publicipaddress'][0]['id']
						@primary_ip = public_ips['listpublicipaddressesresponse']['publicipaddress'][0]['ipaddress']
						pubport = rand(49152..65535)
						while (check_port_available(pubport, primary_public_ip_id) == false)
							pubport = rand(49152..65535)
						end
						add_port_forward(pubport, pubport, server_id, primary_public_ip_id, @sshport)
						@sshport = pubport
					end

					Chef::Log.debug("Connecting over port #{@sshport}")
					config[:ssh_port] = @sshport
					config[:server_name] = @primary_ip
					@template_file = find_template(config[:bootstrap_template])
					
					puts "\n\n"
					puts "#{ui.color("Name", :cyan)}: #{server_display_name}"
					puts "#{ui.color("Primary IP", :cyan)}: #{@primary_ip}"
					puts "#{ui.color("Username", :cyan)}: #{ssh_user}"
					puts "#{ui.color("Password", :cyan)}: #{config[:ssh_password]}"

					print "#{ui.color("Waiting for SSH.", :magenta)}"
					if config[:ssh_gateway]
						Chef::Log.debug("Using SSH Gateway: #{config[:ssh_gateway]}")
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
					end
					begin
						knife_ssh.run
					rescue Net::SSH::AuthenticationFailed
						unless config[:ssh_password]
							ui.info("Failed to authenticate #{config[:ssh_user]} - trying password auth")
							knife_ssh_with_password_auth.run
						end
					rescue Errno::ECONNREFUSED
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue SocketError
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue Errno::ETIMEDOUT
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue Errno::EPERM
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue Errno::EHOSTUNREACH
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue Errno::ENETUNREACH
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue Net::SSH::Disconnect
						sleep @initial_sleep_delay
						print "#{ui.color(".", :magenta)}"
						retry
					rescue
						puts caller
						puts $!.inspect
					end			

					Chef::Log.debug("#{@server}")

					puts "\n"
					puts "#{ui.color("Instance Name", :green)}: #{server_display_name}"
					puts "#{ui.color("Instance ID", :green)}: #{server_id}"
					puts "#{ui.color("Service Offering", :green)}: #{server_serviceoffering}"
					puts "#{ui.color("Template", :green)}: #{server_template}"
					puts "#{ui.color("Public IP Address", :green)}: #{@primary_ip}"
					puts "#{ui.color("Port", :green)}: #{@sshport}"
					puts "#{ui.color("User", :green)}: #{ssh_user}"
					puts "#{ui.color("Password", :green)}: #{config[:ssh_password]}"
					puts "#{ui.color("Environment", :green)}: #{config[:environment] || '_default'}"
					puts "#{ui.color("Run List", :green)}: #{config[:run_list].join(', ')}"
				end

			end
		end
	end
end
