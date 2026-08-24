# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

module GeometryTestHelper
  F = Microsoft::Xna::Framework

  def assert_vector(expected, actual, delta: 0.00001)
    names = %i[X Y Z W].select { |name| expected.respond_to?(name) }
    names.each { |name| assert_in_delta expected.public_send(name), actual.public_send(name), delta, name.to_s }
  end

  def assert_matrix_close(expected, actual, delta: 0.00001)
    (1..4).each do |row|
      (1..4).each do |column|
        name = "M#{row}#{column}"
        assert_in_delta expected.public_send(name), actual.public_send(name), delta, name
      end
    end
  end
end
