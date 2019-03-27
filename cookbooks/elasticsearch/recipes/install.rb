ES = node.elasticsearch

if ES['is_elasticsearch_instance']
  package 'default-jdk'

  package 'elasticsearch' do
    version ES['version']
  end

  directory ES['home'] do
    owner "elasticsearch"
    group "elasticsearch"
    mode 0755
  end

  directory "/data/elasticsearch-#{ES['version']}/data" do
    owner "elasticsearch"
    group "nogroup"
    mode 0755
    action :create
    recursive true
  end

  if File.new("/proc/mounts").readlines.join.match(/\/data\/elasticsearch-#{ES['version']}\/data/)
    Chef::Log.info("Elastic search bind already complete")
  else
    mount "/data/elasticsearch-#{ES['version']}/data" do
      device ES['home']
      fstype "none"
      options "bind,rw"
      action :mount
    end
  end

  # TODO jf
  elasticsearch_classpath = "$ES_HOME/lib/*"
  template "/usr/share/elasticsearch/elasticsearch.in.sh" do
    source "elasticsearch.in.sh.erb"
    mode 0644
    backup 0
    variables(
      :elasticsearch_classpath => elasticsearch_classpath
    )
  end

  # TODO jf
  # Create the jvm.options file
  template "/opt/elasticsearch/config/jvm.options" do
    cookbook "custom-elasticsearch"
    source "jvm.options.erb"
    mode 0644
    backup 0
    variables(
      :Xms => ES['jvm_options']['Xms'],
      :Xmx => ES['jvm_options']['Xmx'],
      :Xss => ES['jvm_options']['Xss']
    )
  end

  # Add log rotation for the elasticsearch logs
  cookbook_file "/etc/logrotate.d/elasticsearch" do
    source "elasticsearch.logrotate"
    owner "root"
    group "root"
    mode "0644"
    backup 0
  end
end

owner_name = node.dna['users'].first['username']
# This portion of the recipe should run on all instances in your environment.
# We are going to drop elasticsearch.yml for you so you can parse it and provide the instances to your application.
if ['solo','app_master','app','util'].include?(node.dna['instance_role'])
  elasticsearch_hosts = []
  node.dna['utility_instances'].each do |instance|
    if instance['name'].include?(ES['instance_name'])
      elasticsearch_hosts << "#{instance['hostname']}:9200"
    end
  end

  nodedna['applications'].each do |app_name, data|
    template "/data/#{app_name}/shared/config/elasticsearch.yml" do
      owner owner_name
      group owner_name
      mode 0660
      source "es.yml.erb"
      backup 0
      variables(:yaml_file => {
        node.dna['environment']['framework_env'] => {
          :hosts => elasticsearch_hosts
        }
      })
    end
  end
end
