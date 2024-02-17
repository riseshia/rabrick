# frozen_string_literal: false

require "test/unit"
require "rabrick/null_io"

class TestNullIO < Test::Unit::TestCase
  def test_gets
    io = Rabrick::NullIO.new
    assert_nil(io.gets)
  end

  def test_read_returns_empty_string_with_non_positive_length
    io = Rabrick::NullIO.new
    assert_equal(io.read(0, nil), "")
  end

  def test_read_returns_nil_when_positive_length_given
    io = Rabrick::NullIO.new
    assert_equal(io.read(1), nil)
  end

  def test_read_returns_nil_and_set_empty_string_in_outbuf_when_outbuf_given
    io = Rabrick::NullIO.new
    outbuf = "some buffer"
    ret = io.read(1, outbuf)
    assert_equal(ret, nil)
    assert_equal(outbuf, "")
  end

  def test_read_given_length_must_be_non_negative
    io = Rabrick::NullIO.new
    assert_raise(ArgumentError) do
      io.read(-1)
    end
  end

  def test_read_given_outbuf_must_be_convertible_to_string
    io = Rabrick::NullIO.new
    assert_raise(TypeError) do
      io.read(0, Object.new)
    end
  end

  def test_each_returns_empty_enumerator
    io = Rabrick::NullIO.new
    assert_kind_of(Enumerator, io.each)
    assert_nil(io.each.next)
  end
end
