# == Schema Information
#
# Table name: cron_schedules
#
#  id         :bigint           not null, primary key
#  schedule   :string           not null
#  service_id :bigint           not null
#
# Indexes
#
#  index_cron_schedules_on_service_id  (service_id)
#
# Foreign Keys
#
#  fk_rails_...  (service_id => services.id)
#
require "test_helper"

class CronScheduleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
