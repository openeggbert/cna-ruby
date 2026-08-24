# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/cna"

class RuntimeFoundationTest < Minitest::Test
  def test_owned_handle_is_idempotent_and_preserved_on_failure
    generation = CNA::Runtime::Generation.new
    releases = 0
    fail_once = true
    handle = CNA::Runtime::NativeHandle.new(
      handle: 42, ownership: CNA::Runtime::Ownership::OWNED, generation: generation,
      release: lambda do |_value|
        if fail_once
          fail_once = false
          raise CNA::OwnerThreadError, "retry"
        end
        releases += 1
      end
    )
    assert_raises(CNA::OwnerThreadError) { handle.dispose }
    assert_equal 42, handle.value
    assert handle.dispose
    refute handle.dispose
    assert_equal 1, releases
  end

  def test_generation_rejects_wrong_thread_and_stale_resources
    generation = CNA::Runtime::Generation.new
    error = Thread.new do
      generation.assert_owner_thread!
      nil
    rescue Exception => exception
      exception
    end.value
    assert_instance_of CNA::OwnerThreadError, error
    generation.invalidate!
    assert_raises(CNA::StaleGenerationError) { generation.assert_valid! }
  end

  def test_resolver_requires_absolute_override
    previous = ENV["CNA_NATIVE_LIBRARY"]
    ENV["CNA_NATIVE_LIBRARY"] = "relative/libcna.so"
    assert_raises(CNA::NativeLoadError) { CNA::Native::Resolver.candidates }
  ensure
    ENV["CNA_NATIVE_LIBRARY"] = previous
  end
end
