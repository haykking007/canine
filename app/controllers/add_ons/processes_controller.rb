class AddOns::ProcessesController < AddOns::BaseController
  include LogColorsHelper

  def index;end

  def show
    client = K8::Client.new(@add_on.cluster.kubeconfig)
    @logs = client.get_pod_log(params[:id], @add_on.name)
  rescue Kubeclient::ResourceNotFoundError
    flash[:alert] = "Pod #{params[:id]} not found"
    redirect_to add_on_processes_path(@add_on)
  end
end
