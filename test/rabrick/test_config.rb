# frozen_string_literal: false

require "test/unit"
require "rabrick/config"

class TestWEBrickConfig < Test::Unit::TestCase
  def test_server_name_default
    config = Rabrick::Config::General.dup
    assert_equal(false, config.key?(:ServerName))
    assert_equal(Rabrick::Utils.getservername, config[:ServerName])
    assert_equal(true, config.key?(:ServerName))
  end

  def test_server_name_set_nil
    config = Rabrick::Config::General.dup.update(ServerName: nil)
    assert_equal(nil, config[:ServerName])
  end
end
