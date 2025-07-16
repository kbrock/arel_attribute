# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = 'spec/*_spec.rb'
end



# require "standard/rake"

task default: :spec # %i[spec standard]