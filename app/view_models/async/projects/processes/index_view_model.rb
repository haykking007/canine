class Async::Projects::Processes::IndexViewModel < Async::BaseViewModel
  expects :project_id
  def project
    @project ||= current_user.projects.find(params[:project_id])
  end

  def initial_render
    render "shared/components/table_skeleton"
  end

  def async_render
    render "processes/pods", locals: {
      pods: get_pods_for_project(project),
      parent: project,
      empty_message: "Nothing running for this project"
    }
  end

  def get_pods_for_project(project)
    # Get all pods for a given namespace
    client = K8::Client.from_project(project).client
    pods = client.get_pods(namespace: project.name)
  end
end
