# frozen_string_literal: true

# on a mac using:
# bundle config --global build.mysql2 "--with-mysql-dir=$(brew --prefix mysql)"

%w[7.2.3 8.0.4 8.1.2].each do |ar_version|
  appraise "gemfile-#{ar_version.split('.').first(2).join}" do
    gem 'activerecord', "~> #{ar_version}"
    gem 'activesupport', "~> #{ar_version}"
    # so we are targeting the ruby version indirectly through active record
    if ar_version < "8.0"
      # sqlite3 v 2.0 is causing trouble with rails
      gem "sqlite3", "< 2.0"
    else
      # Rails 8.0 requires sqlite3 >= 2.1
      gem "sqlite3", ">= 2.1"
    end
  end
end

appraise "rails-edge" do
  gem "rails", github: "rails/rails", branch: "main"
end
