class Clusters::InstallMetricServer
  extend LightService::Action

  expects :cluster

  executed do |context|
    cluster = context.cluster
    runner = Cli::RunAndLog.new(cluster)
    kubectl = K8::Kubectl.new(cluster.kubeconfig, runner)
    cluster.info("Checking if metric server is already installed...")

    begin
      kubectl.("get deployment metrics-server -n kube-system")
      cluster.info("Nginx ingress controller is already installed")
    rescue Cli::CommandFailedError => e
      cluster.info("Metric server not detected, installing...")
      kubectl.apply_yaml(Rails.root.join("resources", "k8", "shared", "metrics_server.yaml"))
    end
  end
end