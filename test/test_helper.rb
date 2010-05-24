require 'tempfile'
require 'pp'
require 'shoulda'
#require 'matchy'
require 'mocha'
require 'mongoid'

require File.expand_path(File.dirname(__FILE__) + '/../lib/mongoid/grid')

Mongoid.configure do |config|
  name = "mongoid_grid_test"
  host = "localhost"
  config.allow_dynamic_fields = false
  config.master = Mongo::Connection.new.db(name)
end

class Test::Unit::TestCase
  def setup
    Mongoid.database.collections.each(&:remove)
  end

  def assert_difference(expression, difference = 1, message = nil, &block)
    b      = block.send(:binding)
    exps   = Array.wrap(expression)
    before = exps.map { |e| eval(e, b) }
    yield
    exps.each_with_index do |e, i|
      error = "#{e.inspect} didn't change by #{difference}"
      error = "#{message}.\n#{error}" if message
      assert_equal(before[i] + difference, eval(e, b), error)
    end
  end

  def assert_no_difference(expression, message = nil, &block)
    assert_difference(expression, 0, message, &block)
  end

  def assert_grid_difference(difference=1, &block)
    assert_difference("Mongoid.database['fs.files'].find().count", difference, &block)
  end

  def assert_no_grid_difference(&block)
    assert_grid_difference(0, &block)
  end
end