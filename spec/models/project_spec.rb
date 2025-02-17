# == Schema Information
#
# Table name: projects
#
#  id                             :bigint           not null, primary key
#  autodeploy                     :boolean          default(TRUE), not null
#  branch                         :string           default("main"), not null
#  container_registry_url         :string
#  docker_build_context_directory :string           default("."), not null
#  docker_command                 :string
#  dockerfile_path                :string           default("./Dockerfile"), not null
#  name                           :string           not null
#  predeploy_command              :string
#  repository_url                 :string           not null
#  status                         :integer          default("creating"), not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  cluster_id                     :bigint           not null
#
# Indexes
#
#  index_projects_on_cluster_id  (cluster_id)
#  index_projects_on_name        (name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (cluster_id => clusters.id)
#
require 'rails_helper'

RSpec.describe Project, type: :model do
  let(:cluster) { create(:cluster) }
  let(:project) { build(:project, cluster: cluster) }

  describe 'validations' do
    context 'when name is not unique to the cluster' do
      before do
        create(:project, name: project.name, cluster: cluster)
      end

      it 'is not valid' do
        expect(project).not_to be_valid
        expect(project.errors[:name]).to include("must be unique to this cluster")
      end
    end
  end

  describe '#current_deployment' do
    it 'returns the most recent completed deployment' do
      completed_deployment = create(:deployment, project: project, status: :completed)
      create(:deployment, project: project, status: :in_progress)

      expect(project.current_deployment).to eq(completed_deployment)
    end
  end

  describe '#last_build' do
    it 'returns the most recent build' do
      create(:build, project: project)
      last_build = create(:build, project: project)

      expect(project.last_build).to eq(last_build)
    end
  end

  describe '#last_deployment' do
    it 'returns the most recent deployment' do
      create(:deployment, project: project)
      last_deployment = create(:deployment, project: project)

      expect(project.last_deployment).to eq(last_deployment)
      expect(project.last_deployment_at).to eq(last_deployment.created_at)
    end
  end

  describe '#repository_name' do
    it 'returns the name of the repository from the repository_url' do
      project.repository_url = 'owner/repository-name'
      expect(project.repository_name).to eq('repository-name')
    end
  end

  describe '#full_repository_url' do
    it 'returns the full GitHub URL' do
      project.repository_url = 'owner/repository-name'
      expect(project.full_repository_url).to eq('https://github.com/owner/repository-name')
    end
  end

  describe '#deployable?' do
    it 'returns true if there are services' do
      create(:service, project: project)
      expect(project.deployable?).to be true
    end

    it 'returns false if there are no services' do
      expect(project.deployable?).to be false
    end
  end

  describe '#has_updates?' do
    it 'returns true if any service is updated or pending' do
      create(:service, project: project, status: :updated)
      expect(project.has_updates?).to be true
    end

    it 'returns false if no services are updated or pending' do
      create(:service, project: project, status: :healthy)
      expect(project.has_updates?).to be false
    end
  end
end
