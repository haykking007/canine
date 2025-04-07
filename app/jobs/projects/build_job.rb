# frozen_string_literal: true

require 'shellwords'

class Projects::BuildJob < ApplicationJob
  queue_as :default
  class BuildFailure < StandardError; end

  def perform(build)
    project = build.project
    # If its a dockerhub deploy, we don't need to build the docker image
    if project.github?
      project_credential_provider = project.project_credential_provider
      project_credential_provider.used!

      clone_repository_and_build_docker(project, build)

      login_to_docker(project_credential_provider, build)

      push_to_github_container_registry(project, build)
    else
      build.info("Skipping build for #{project.name} because it's a Docker Hub deploy")
    end

    complete_build!(build)
    # TODO: Step 7: Optionally, add post-deploy tasks or slack notifications
  rescue BuildFailure => e
    build.error(e.message)
    build.failed!
  end

  private

  def project_git(project)
    project_credential_provider = project.project_credential_provider
    "https://#{project_credential_provider.username}:#{project_credential_provider.access_token}@github.com/#{project.repository_url}.git"
  end

  def git_clone(project, build, repository_path)
    # Construct the git clone command with OAuth token
    git_clone_command = %w[git clone --depth 1 --branch] +
                        [ project.branch, project_git(project), repository_path ]

    # Execute the git clone command
    _stdout, stderr, status = Open3.capture3(*git_clone_command)

    raise BuildFailure, "Failed to clone repository: #{stderr}" unless status.success?

    build.success("Repository cloned successfully to #{repository_path}.")
  end

  def build_docker_build_command(project, repository_path)
    docker_build_command = [
      "docker", "build",
      "--progress=plain",
      "--platform", "linux/amd64",
      "-t", project.container_registry_url,
      "-f", File.join(repository_path, project.dockerfile_path)
    ]

    # Add environment variables to the build command
    project.environment_variables.each do |envar|
      docker_build_command.push("--build-arg", "#{envar.name}=\"#{envar.value}\"")
    end

    # Add the build context directory at the end
    docker_build_command.push(File.join(repository_path, project.docker_build_context_directory))
    docker_build_command
  end

  def execute_docker_build(project, build, repository_path)
    docker_build_command = build_docker_build_command(project, repository_path)

    # Create a new instance of RunAndLog with the build object as the loggable
    runner = Cli::RunAndLog.new(build)

    # Call the runner with the command (joined as a string since RunAndLog expects a string)
    exit_status = runner.call(docker_build_command.join(" "))
  rescue Cli::CommandFailedError => e
    raise BuildFailure, e.message
  end

  def login_to_docker(project_credential_provider, build)
    docker_login_command = %w[docker login ghcr.io --username] +
                           [ project_credential_provider.username, "--password", project_credential_provider.access_token ]

    build.info("Logging into ghcr.io as #{project_credential_provider.username}", color: :yellow)
    _stdout, stderr, status = Open3.capture3(*docker_login_command)

    if status.success?
      build.success("Logged in to Github Container Registry successfully.")
    else
      build.error("Github Container Registry login failed with error:\n#{stderr}")
    end
  end

  def push_to_github_container_registry(project, build)
    docker_push_command = [ "docker", "push", project.container_registry_url ]

    build.info("Pushing Docker image to #{docker_push_command.last}", color: :yellow)
    stdout, stderr, status = Open3.capture3(*docker_push_command)

    raise BuildFailure, "Docker push failed for project #{project.name} with error:\n#{stderr}" unless status.success?

    build.success("Docker image pushed to `#{project.container_registry_url}` successfully for project #{project.name}:\n#{stdout}")
  end

  def complete_build!(build)
    build.completed!
    deployment = Deployment.create!(build:)
    Projects::DeploymentJob.perform_later(deployment)
  end

  def clone_repository_and_build_docker(project, build)
    Dir.mktmpdir do |repository_path|
      build.info("Cloning repository: #{project.repository_url} to #{repository_path}", color: :yellow)

      # Ensure the temporary directory doesn't exist
      FileUtils.rm_rf(repository_path) if Dir.exist?(repository_path)

      git_clone(project, build, repository_path)

      execute_docker_build(project, build, repository_path)
    rescue StandardError => e
      raise BuildFailure, "Build failed: #{e.message}"
    end
  end
end
