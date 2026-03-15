ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Rails 7.1's line filtering extension expects the older minitest run signature.
module Rails
  module LineFiltering
    def run(*args, **kwargs)
      super(*args, **kwargs)
    end

    def run_suite(reporter, options = {})
      options = options.merge(filter: Rails::TestUnit::Runner.compose_filter(self, options[:filter]))

      super
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
