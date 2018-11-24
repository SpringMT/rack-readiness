source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in rack-readiness.gemspec
gemspec

group :development, :test do
  gem 'pry'
end
group :test do
  gem 'rack'
  gem 'timecop'
end
