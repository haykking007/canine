class K8::Helm::Service
  attr_reader :add_on, :client

  def initialize(add_on)
    @add_on = add_on
    @client = K8::Client.new(add_on.cluster.kubeconfig)
  end

  def storage_metrics
    pods = client.pods_for_service(service_name)
    volumes = pods.flat_map do |pod|
      pod.spec.volumes.select { |volume| volume.respond_to?(:persistentVolumeClaim) && volume.persistentVolumeClaim.claimName }
    end
  
    pvc_names = volumes.map { |volume| volume.persistentVolumeClaim.claimName }
    pvcs = client.get_persistent_volume_claims(
      namespace: 'default',
      field_selector: "metadata.name=#{pvc_names.join(',')}"
    ).flatten
  
    pvcs.map do |pvc|
      pod = pods.find { |p| p.spec.volumes.any? { |vol| vol.persistentVolumeClaim&.claimName == pvc.metadata.name } }
      mount_path = get_mount_path(pod, pvc.metadata.name) if pod
      usage = mount_path ? get_volume_usage(pod.metadata.name, mount_path) : nil
  
      {
        name: pvc.metadata.name,
        usage: usage
      }
    end
  end

  def version
    services = K8::Helm::Client.new(add_on.cluster.kubeconfig, Cli::RunAndReturnOutput.new).ls
    chart = services.find { |service| service.name == add_on.name }.chart
    chart.match(/\d+\.\d+\.\d+/)&.to_s
  end

  private
  def get_mount_path(pod, pvc_name)
    volume = pod.spec.volumes.find { |vol| vol.persistentVolumeClaim&.claimName == pvc_name }
    return nil unless volume
  
    container = pod.spec.containers.find { |c| c.volumeMounts.any? { |vm| vm.name == volume.name } }
    container&.volumeMounts&.find { |vm| vm.name == volume.name }&.mountPath
  end
  
  def get_volume_usage(pod_name, mount_path)
    output = K8::Kubectl.new(add_on.cluster.kubeconfig, Cli::RunAndReturnOutput.new).call("exec #{pod_name} -- df -h #{mount_path}")
    lines = output.strip.split("\n")
    return nil if lines.size < 2
  
    usage_line = lines[1].split
    {
      used: usage_line[2],
      available: usage_line[3],
      use_percentage: usage_line[4].to_i
    }
  end

  def get_persistent_volume
    pv = K8::Kubectl.new(add_on.cluster.kubeconfig, Cli::RunAndReturnOutput.new).call("get pv #{service_name} -o json")
    JSON.parse(pv)
  end

  def exec_df_command
    output = K8::Kubectl.new(add_on.cluster.kubeconfig, Cli::RunAndReturnOutput.new).call("exec #{service_name} -- df -h /data")
    output.strip
  end

end