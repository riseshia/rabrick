# frozen_string_literal: false

require "test/unit"
require "rabrick"

class TestWEBrickHTTPStatus < Test::Unit::TestCase
  def test_info?
    assert Rabrick::HTTPStatus.info?(100)
    refute Rabrick::HTTPStatus.info?(200)
  end

  def test_success?
    assert Rabrick::HTTPStatus.success?(200)
    refute Rabrick::HTTPStatus.success?(300)
  end

  def test_redirect?
    assert Rabrick::HTTPStatus.redirect?(300)
    refute Rabrick::HTTPStatus.redirect?(400)
  end

  def test_error?
    assert Rabrick::HTTPStatus.error?(400)
    refute Rabrick::HTTPStatus.error?(600)
  end

  def test_client_error?
    assert Rabrick::HTTPStatus.client_error?(400)
    refute Rabrick::HTTPStatus.client_error?(500)
  end

  def test_server_error?
    assert Rabrick::HTTPStatus.server_error?(500)
    refute Rabrick::HTTPStatus.server_error?(600)
  end
end
