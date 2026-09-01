# frozen_string_literal: true

require "json"
require_relative "name_mapper"

module CNAApiCompat
  CATEGORIES = %w[
    MISSING_TYPE MISSING_MEMBER UNEXPECTED_TYPE UNEXPECTED_MEMBER TYPE_KIND_MISMATCH
    BASE_MAPPING_MISMATCH INTERFACE_MAPPING_MISMATCH FIELD_MAPPING_MISMATCH
    PROPERTY_MAPPING_MISMATCH METHOD_SIGNATURE_MAPPING_MISMATCH PARAMETER_MAPPING_MISMATCH
    RETURN_MAPPING_MISMATCH OVERLOAD_MAPPING_MISMATCH GENERIC_MAPPING_MISMATCH
    ENUM_VALUE_MISMATCH FLAGS_MAPPING_MISMATCH EVENT_MAPPING_MISMATCH
    OPERATOR_MAPPING_MISMATCH LANGUAGE_MAPPING_MISMATCH INTERNAL_TYPE_LEAK RAW_HANDLE_LEAK
    PUBLIC_NATIVE_FFI_LEAK UNMEASURED_STRUCTURAL_CATEGORY
  ].freeze

  OPERATOR_METHODS = {
    "op_UnaryNegation" => "-@", "op_Equality" => "==", "op_Inequality" => "!=",
    "op_Addition" => "+", "op_Subtraction" => "-", "op_Multiply" => "*", "op_Division" => "/"
  }.freeze

  LANGUAGE_TYPE_MAPPINGS = {
    "System.IntPtr" => {
      "rubyType" => "Integer", "signed" => true, "width" => "native-pointer",
      "nativeBoundary" => "fixed-width unsigned C carrier containing the signed pointer bit pattern"
    }
  }.freeze

  # One CLR public event identity projects to exactly one public Ruby event reader keeping the XNA
  # spelling, whose value is the generic event subscription primitive. add_Name/remove_Name pairs,
  # a writer, an ordinary mutable property and any consumer-facing raise helper are all mapping
  # failures rather than acceptable alternatives.
  EVENT_SUPPORT_TYPE = "CNA::Runtime::Event"
  EVENT_SUPPORT_SURFACE = %i[add remove].freeze
  EVENT_RAISE_NAMES = %i[broadcast call dispatch emit fire invoke notify publish raise_event trigger].freeze

  class Result
    attr_reader :counts, :details, :complete_types, :partial_types, :missing_types

    def initialize
      @counts = CATEGORIES.to_h { |category| [category, 0] }
      @details = CATEGORIES.to_h { |category| [category, []] }
      @type_diagnostics = Hash.new(0)
      @complete_types = []
      @partial_types = {}
      @missing_types = []
    end

    def add(category, detail, type: nil, count: 1)
      counts.fetch(category)
      counts[category] += count
      details[category] << detail
      @type_diagnostics[type] += count if type
    end

    def type_diagnostics(name) = @type_diagnostics[name]
  end

  class Verifier
    attr_reader :reference, :target, :runtime

    def initialize(reference:, target:, runtime: false)
      @reference = reference
      @target = target
      @runtime = runtime
    end

    def verify
      result = Result.new
      target.fetch("unmeasuredCategories", []).each do |category|
        result.add("UNMEASURED_STRUCTURAL_CATEGORY", category)
      end
      reference_types = reference.fetch("types").to_h { |type| [type.fetch("name"), mapped_type(type)] }
      target_types = target.fetch("types").to_h { |type| [type.fetch("name"), type] }

      (reference_types.keys - target_types.keys).sort.each do |name|
        result.missing_types << name
        result.add("MISSING_TYPE", name, type: name)
      end
      (target_types.keys - reference_types.keys).sort.each do |name|
        result.add("UNEXPECTED_TYPE", name, type: name)
      end

      (reference_types.keys & target_types.keys).sort.each do |name|
        compare_type(reference_types.fetch(name), target_types.fetch(name), result)
      end
      verify_language_type_mappings(target_types, result)
      verify_runtime(target_types, result) if runtime
      verify_public_leaks(target_types, result) if runtime

      target_types.each_key do |name|
        next unless reference_types.key?(name)
        if result.type_diagnostics(name).zero? && target_types[name].fetch("members").length == reference_types[name].fetch("members").length
          result.complete_types << name
        else
          missing = result.details["MISSING_MEMBER"].grep(/^#{Regexp.escape(name)}::/)
          result.partial_types[name] = missing
        end
      end
      result
    end

    private

    def mapped_type(type)
      type.merge("members" => type.fetch("members").reject { |member| type["kind"] == "enum" && member["name"] == "value__" })
    end

    def group_key(member) = [member["kind"], member["static"], member["name"]]

    def compare_type(expected, actual, result)
      name = expected.fetch("name")
      result.add("TYPE_KIND_MISMATCH", "#{name}: expected #{expected["kind"]}, got #{actual["kind"]}", type: name) unless expected["kind"] == actual["kind"]
      result.add("BASE_MAPPING_MISMATCH", "#{name}: expected #{expected["baseType"].inspect}, got #{actual["baseType"].inspect}", type: name) unless expected["baseType"] == actual["baseType"]
      result.add("INTERFACE_MAPPING_MISMATCH", name, type: name) unless expected.fetch("interfaces", []) == actual.fetch("interfaces", []) && expected.fetch("directInterfaces", []) == actual.fetch("directInterfaces", [])
      result.add("GENERIC_MAPPING_MISMATCH", "#{name} type generic parameters", type: name) unless expected.fetch("genericParameters", []) == actual.fetch("genericParameters", [])
      result.add("FLAGS_MAPPING_MISMATCH", name, type: name) unless expected.fetch("flags", false) == actual.fetch("flags", false)
      if expected["kind"] == "enum" && expected["underlyingType"] != actual["underlyingType"]
        result.add("ENUM_VALUE_MISMATCH", "#{name}: underlying type", type: name)
        result.add("FLAGS_MAPPING_MISMATCH", "#{name}: flags underlying type", type: name) if expected.fetch("flags", false)
      end
      expected_ruby_name = NameMapper.runtime_constant_path(name)
      result.add("LANGUAGE_MAPPING_MISMATCH", "#{name}: #{actual["rubyName"].inspect}", type: name) unless actual["rubyName"] == expected_ruby_name

      expected_groups = expected.fetch("members").group_by { |member| group_key(member) }
      actual_groups = actual.fetch("members").group_by { |member| group_key(member) }
      (expected_groups.keys | actual_groups.keys).each do |key|
        expected_members = expected_groups.fetch(key, [])
        actual_members = actual_groups.fetch(key, [])
        difference = expected_members.length - actual_members.length
        if difference.positive?
          result.add("MISSING_MEMBER", "#{name}::#{key[2]} (#{difference} overload#{difference == 1 ? "" : "s"})", type: name, count: difference)
        elsif difference.negative?
          result.add("UNEXPECTED_MEMBER", "#{name}::#{key[2]} (#{-difference} overload#{difference == -1 ? "" : "s"})", type: name, count: -difference)
        end
        if expected_members.length != actual_members.length && ["method", "constructor"].include?(key[0])
          result.add("OVERLOAD_MAPPING_MISMATCH", "#{name}::#{key[2]} expected #{expected_members.length}, got #{actual_members.length}", type: name)
        end
        pair_members(expected_members, actual_members).each do |expected_member, actual_member|
          compare_member(name, expected_member, actual_member, result)
        end
      end
    end

    def pair_members(expected, actual)
      remaining_expected = expected.dup
      remaining_actual = actual.dup
      pairs = []
      actual.each do |member|
        exact = remaining_expected.index { |candidate| parameters(candidate) == parameters(member) }
        next unless exact
        expected_member = remaining_expected.delete_at(exact)
        remaining_actual.delete(member)
        pairs << [expected_member, member]
      end
      pairs.concat(remaining_expected.zip(remaining_actual).select { |left, right| left && right })
      pairs
    end

    def parameters(member) = member.fetch("parameters", [])

    def member_types(member)
      [member["type"], member["returnType"], *parameters(member).map { |parameter| parameter["type"] }].compact
    end

    def verify_language_type_mappings(target_types, result)
      mappings = target.fetch("languageTypeMappings", {})
      LANGUAGE_TYPE_MAPPINGS.each do |source_type, expected|
        users = target_types.filter_map do |name, type|
          name if type.fetch("members").any? { |member| member_types(member).include?(source_type) }
        end
        next if users.empty? || mappings[source_type] == expected

        users.each do |name|
          result.add(
            "LANGUAGE_MAPPING_MISMATCH",
            "#{name}: #{source_type} expected #{expected.inspect}, got #{mappings[source_type].inspect}",
            type: name
          )
        end
      end
    end

    def compare_member(type_name, expected, actual, result)
      label = "#{type_name}::#{expected["name"]}"
      kind = expected.fetch("kind")
      if %w[method constructor].include?(kind)
        result.add("PARAMETER_MAPPING_MISMATCH", label, type: type_name) unless parameters(expected) == parameters(actual)
        result.add("RETURN_MAPPING_MISMATCH", label, type: type_name) unless expected["returnType"] == actual["returnType"]
        result.add("METHOD_SIGNATURE_MAPPING_MISMATCH", label, type: type_name) unless expected["access"] == actual["access"] && expected["static"] == actual["static"]
        result.add("GENERIC_MAPPING_MISMATCH", "#{label} generic parameters", type: type_name) unless expected.fetch("genericParameters", []) == actual.fetch("genericParameters", [])
        if expected["name"].start_with?("op_") && projected_signature(expected) != projected_signature(actual)
          result.add("OPERATOR_MAPPING_MISMATCH", label, type: type_name)
        end
      elsif kind == "property"
        keys = %w[type static get set getAccess setAccess parameters]
        result.add("PROPERTY_MAPPING_MISMATCH", label, type: type_name) unless keys.all? { |key| expected[key] == actual[key] }
      elsif kind == "field"
        keys = %w[type static access]
        result.add("FIELD_MAPPING_MISMATCH", label, type: type_name) unless keys.all? { |key| expected[key] == actual[key] }
        if expected["value"] != actual["value"]
          category = expected["type"] == type_name ? "ENUM_VALUE_MISMATCH" : "FIELD_MAPPING_MISMATCH"
          result.add(category, label, type: type_name)
        end
      elsif kind == "event"
        result.add("EVENT_MAPPING_MISMATCH", label, type: type_name) unless projected_signature(expected) == projected_signature(actual)
      end
    end

    def projected_signature(member)
      member.reject { |key, _| %w[name].include?(key) }
    end

    def resolve_ruby_type(name)
      name.split("::").reduce(Object) { |context, constant| context.const_get(constant, false) }
    end

    def verify_runtime(target_types, result)
      verify_bcl_projection(result)
      verify_event_support_type(target_types, result)
      target_types.each do |name, type|
        ruby_name = type.fetch("rubyName")
        begin
          object = resolve_ruby_type(ruby_name)
        rescue NameError
          result.add("MISSING_TYPE", "runtime #{ruby_name}", type: name)
          next
        end
        expected_runtime_kind = %w[class struct enum delegate].include?(type["kind"]) ? Class : Module
        result.add("TYPE_KIND_MISMATCH", "runtime #{ruby_name}", type: name) unless object.instance_of?(expected_runtime_kind)
        if type["kind"] == "enum" && object.instance_variable_get(:@enum_flags) != type.fetch("flags", false)
          result.add("FLAGS_MAPPING_MISMATCH", "runtime #{ruby_name}", type: name)
        end
        if type["kind"] == "enum" && type.fetch("flags", false)
          expected_mask = type.fetch("members").select { |member| member["kind"] == "field" }
                              .reduce(0) { |mask, member| mask | Integer(member.fetch("value")) }
          if object.instance_variable_get(:@enum_mask) != expected_mask
            result.add("FLAGS_MAPPING_MISMATCH", "runtime #{ruby_name} combined-value mask", type: name)
          end
        end
        verify_runtime_base(name, type, object, result)
        verify_runtime_interfaces(name, type, object, target_types, result)
        verify_runtime_events(name, type, object, result)
        type.fetch("members").each do |member|
          missing = ruby_projections(member).reject { |projection| projection_exists?(object, projection, member) }
          next if missing.empty?
          result.add("MISSING_MEMBER", "#{name}::#{member["name"]} runtime #{missing.join(",")}", type: name, count: missing.length)
        end
      end
    end

    # Every entry of the measured BCL projection register must resolve, and an exception base must
    # really be a Ruby exception class. Without this the register could claim a projection the
    # runtime does not carry, and the dependency frontier would inherit that claim.
    def verify_bcl_projection(result)
      CNA::Runtime::BclProjection::TYPES.each do |clr_identity, ruby_path|
        resolve_ruby_type(ruby_path)
      rescue NameError
        result.add("LANGUAGE_MAPPING_MISMATCH", "BCL projection #{clr_identity}: #{ruby_path} does not resolve")
      end
      CNA::Runtime::BclProjection::EXCEPTION_BASES.each do |clr_identity, ruby_path|
        base = begin
          resolve_ruby_type(ruby_path)
        rescue NameError
          result.add("LANGUAGE_MAPPING_MISMATCH", "BCL exception base #{clr_identity}: #{ruby_path} does not resolve")
          next
        end
        next if base.instance_of?(Class) && base <= ::Exception && base <= ::StandardError

        result.add("LANGUAGE_MAPPING_MISMATCH", "BCL exception base #{clr_identity}: #{ruby_path} is not a Ruby StandardError class")
      end
      verify_thrown_exceptions(result)
      verify_structural_collapse(result)
    end

    # A structurally collapsed BCL identity must really have no Ruby constant. The register records
    # a decision *not* to invent one, and this is what stops that decision from quietly turning into
    # an invented module later: neither a fabricated ::System namespace nor a CNA runtime constant
    # named after the CLR identity may exist.
    def verify_structural_collapse(result)
      CNA::Runtime::BclProjection::STRUCTURAL_COLLAPSE.each_key do |clr_identity|
        # A generic identity's short name is `Action`1`, which is not a Ruby constant name at all,
        # so `const_defined?` raises on it rather than answering false. The names that *could* be
        # invented for it are the bare `Action` and the `NameOfT` spelling `mapping-rules.json`
        # `generics.runtimeTypeName` reserves for a projected generic, and both are checked.
        definition = clr_identity.split(".").last
        arity = definition[/`(\d+)\z/, 1]
        base = definition.sub(/`\d+\z/, "")
        candidates = [base]
        candidates << "#{base}Of#{arity.to_i == 1 ? "T" : (1..arity.to_i).map { |n| "T#{n}" }.join}" if arity
        candidates.map(&:to_sym).each do |short|
          [Object, CNA::Runtime].each do |scope|
            next unless scope.const_defined?(short, false)

            result.add("LANGUAGE_MAPPING_MISMATCH",
                       "BCL structural collapse #{clr_identity}: #{scope}::#{short} was invented")
          end
        end
        next unless clr_identity.include?(".") && Object.const_defined?(clr_identity.split(".").first.to_sym, false)

        result.add("LANGUAGE_MAPPING_MISMATCH",
                   "BCL structural collapse #{clr_identity}: a fabricated #{clr_identity.split(".").first} namespace exists")
      end
    end

    # A CLR exception a projected member throws must raise a Ruby exception an ordinary `rescue`
    # catches, because a CLR `catch (Exception)` is exactly that. Ruby's NotImplementedError is the
    # trap this check exists for: it reads like the right name and descends from ScriptError, so a
    # bare rescue misses it and a routine, recoverable CLR failure would escape the caller's error
    # handling entirely.
    def verify_thrown_exceptions(result)
      CNA::Runtime::BclProjection::THROWN_EXCEPTIONS.each do |clr_identity, ruby_path|
        raised = begin
          resolve_ruby_type(ruby_path)
        rescue NameError
          result.add("LANGUAGE_MAPPING_MISMATCH", "BCL thrown exception #{clr_identity}: #{ruby_path} does not resolve")
          next
        end
        unless raised.instance_of?(Class) && raised <= ::StandardError
          result.add("LANGUAGE_MAPPING_MISMATCH",
                     "BCL thrown exception #{clr_identity}: #{ruby_path} is not a Ruby StandardError class")
          next
        end
        next unless raised <= ::ScriptError || raised.equal?(::NotImplementedError)

        result.add("LANGUAGE_MAPPING_MISMATCH",
                   "BCL thrown exception #{clr_identity}: #{ruby_path} escapes an ordinary rescue")
      end
    end

    def verify_runtime_base(name, type, object, result)
      return if object.instance_of?(Module) && !object.instance_of?(Class)

      base = type["baseType"]
      projected = CNA::Runtime::BclProjection.ruby_type(base)
      expected = if base&.start_with?("Microsoft.Xna.") && target.fetch("types").any? { |candidate| candidate["name"] == base }
                   resolve_ruby_type(NameMapper.runtime_constant_path(base))
                 elsif type["kind"] == "enum"
                   CNA::Runtime::EnumValue
                 elsif projected
                   # A non-XNA CLR base the binding projects: an XNA exception takes a Ruby
                   # exception superclass rather than Object, and an XNA collection whose CLR base
                   # is a projected BCL generic takes the runtime support class rather than Array.
                   resolve_ruby_type(projected)
                 else
                   Object
                 end
      unless object.superclass == expected
        result.add("BASE_MAPPING_MISMATCH", "runtime #{name}: expected #{expected}, got #{object.superclass}", type: name)
      end
      verify_bcl_generic_base(name, base, object, result)
    end

    # A CLR class whose base is a registered BCL *generic* projection has to keep two things, not
    # one. The Ruby superclass must be the registered support class -- which the check above already
    # settles, so an Array substitution, an Object fallback or an invented ::System constant all
    # fail there. And the CLR type argument must survive, which the superclass expression cannot
    # carry because a Ruby class is not statically generic. The support class records it as
    # metadata and this is where that metadata is measured against the reference contract.
    def verify_bcl_generic_base(name, base, object, result)
      return unless base && CNA::Runtime::BclProjection.generic_projection?(base)

      expected = CNA::Runtime::BclProjection.element_types(base)
      actual = object.respond_to?(:clr_element_types) ? object.clr_element_types : nil
      return if actual == expected

      result.add(
        "GENERIC_MAPPING_MISMATCH",
        "runtime #{name}: #{CNA::Runtime::BclProjection.definition(base)} element projection " \
        "expected #{expected.inspect}, got #{actual.inspect}",
        type: name
      )
    end

    def verify_runtime_interfaces(name, type, object, target_types, result)
      return unless name.start_with?("Microsoft.Xna.Framework.Graphics.PackedVector.")

      type.fetch("interfaces", []).each do |interface_identity|
        definition_identity = interface_identity.sub(/\[.*\]\z/, "")
        next unless target_types.key?(definition_identity)

        interface = resolve_ruby_type(NameMapper.runtime_constant_path(definition_identity))
        next if object.ancestors.include?(interface)

        result.add(
          "INTERFACE_MAPPING_MISMATCH",
          "runtime #{name}: missing #{definition_identity}",
          type: name
        )
      end

      return if type["kind"] == "interface"

      abstract_owners = [
        resolve_ruby_type(NameMapper.runtime_constant_path("Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector")),
        resolve_ruby_type(NameMapper.runtime_constant_path("Microsoft.Xna.Framework.Graphics.PackedVector.IPackedVector`1"))
      ]
      %i[PackFromVector4 ToVector4 PackedValue PackedValue=].each do |method_name|
        next unless object.method_defined?(method_name) || object.private_method_defined?(method_name)
        next unless abstract_owners.include?(object.instance_method(method_name).owner)

        result.add(
          "MISSING_MEMBER",
          "runtime #{name}: #{method_name} is only the abstract interface projection",
          type: name
        )
      end
    end

    # The generic subscription primitive is checked once, not per owner: its whole public surface
    # must stay add/remove so that no consumer-facing raise helper can appear behind an event.
    def verify_event_support_type(target_types, result)
      owners = target_types.select do |_name, type|
        type.fetch("members").any? { |member| member.fetch("kind") == "event" }
      end
      return if owners.empty?

      support = resolve_ruby_type(EVENT_SUPPORT_TYPE)
      surface = (support.public_instance_methods(false) + support.protected_instance_methods(false)).sort
      unless surface == EVENT_SUPPORT_SURFACE
        result.add("EVENT_MAPPING_MISMATCH", "#{EVENT_SUPPORT_TYPE} subscription surface #{surface.inspect}")
      end
      leaked = EVENT_RAISE_NAMES.select { |candidate| support.public_method_defined?(candidate) }
      return if leaked.empty?

      result.add("EVENT_MAPPING_MISMATCH", "#{EVENT_SUPPORT_TYPE} exposes public #{leaked.join(", ")}")
    end

    # Selected event identities are measured rather than assumed: the declared set must match the
    # set the runtime projection registers through the generic primitive, no add_/remove_ or writer
    # identity may exist beside the reader, and the reader's value must be the primitive itself
    # (or, on an abstract XNA interface, the same NotImplementedError every other member raises).
    def verify_runtime_events(name, type, object, result)
      declared = type.fetch("members").select { |member| member.fetch("kind") == "event" }
                     .map { |member| member.fetch("name").to_sym }
      registered = object.respond_to?(:xna_event_identities) ? object.xna_event_identities : []
      return if declared.empty? && registered.empty?

      (declared - registered).each do |identity|
        result.add("EVENT_MAPPING_MISMATCH", "#{name}::#{identity} is not declared through #{EVENT_SUPPORT_TYPE}", type: name)
      end
      (registered - declared).each do |identity|
        result.add("EVENT_MAPPING_MISMATCH", "#{name}::#{identity} runtime event identity is not selected", type: name)
      end

      abstract = type["kind"] == "interface"
      probe = event_probe(object)
      declared.each do |identity|
        %W[add_#{identity} remove_#{identity} #{identity}=].each do |leaked|
          next unless object.method_defined?(leaked) || object.private_method_defined?(leaked)

          result.add("EVENT_MAPPING_MISMATCH", "#{name}::#{identity} also projects #{leaked}", type: name)
        end
        projected = event_projection(probe, identity, abstract)
        next if projected == :expected

        result.add("EVENT_MAPPING_MISMATCH", "#{name}::#{identity} projects #{projected}", type: name)
      end
    end

    # An uninitialised instance is enough: the generated reader creates its invocation list lazily,
    # and an abstract contract needs only a host that includes the module.
    def event_probe(object)
      host = object.instance_of?(Class) ? object : Class.new { include(object) }
      host.allocate
    rescue StandardError, NotImplementedError
      nil
    end

    def event_projection(probe, identity, abstract)
      return "no probe instance" if probe.nil?

      begin
        value = probe.public_send(identity)
      rescue NotImplementedError
        return abstract ? :expected : "an abstract contract"
      rescue StandardError => error
        return error.class.to_s
      end
      return "a value where the abstract contract is expected" if abstract

      value.instance_of?(resolve_ruby_type(EVENT_SUPPORT_TYPE)) ? :expected : value.class.to_s
    end

    def ruby_projections(member)
      case member.fetch("kind")
      when "constructor" then ["instance:initialize"]
      when "method"
        operator = OPERATOR_METHODS[member["name"]]
        ["instance:#{operator || member["name"]}"] unless member["static"] && !operator
        member["static"] && !operator ? ["class:#{member["name"]}"] : ["instance:#{operator || member["name"]}"]
      when "property"
        scope = member["static"] ? "class" : "instance"
        getter = member["name"] == "Item" ? "[]" : member["name"]
        setter = member["name"] == "Item" ? "[]=" : "#{member["name"]}="
        [member["get"] ? "#{scope}:#{getter}" : nil,
         member["set"] ? "#{scope}:#{setter}" : nil].compact
      when "field"
        if member["static"]
          ["constant:#{member["name"]}"]
        else
          ["instance:#{member["name"]}", "instance:#{member["name"]}="]
        end
      when "event"
        # Exactly one identity: the reader. Never an add_/remove_ pair and never a writer.
        [member["static"] ? "class:#{member["name"]}" : "instance:#{member["name"]}"]
      else
        []
      end
    end

    def projection_exists?(object, projection, member)
      scope, name = projection.split(":", 2)
      case scope
      when "constant"
        return false unless object.const_defined?(name, false)
        value = object.const_get(name, false)
        return value.to_i == Integer(member["value"]) if object < CNA::Runtime::EnumValue
        return true unless member["constant"]
        expected = member["value"]
        expected.to_s.include?(".") ? format("%.7g", value) == expected.to_s : value == Integer(expected)
      when "class" then object.respond_to?(name, true)
      when "instance"
        symbol = name.to_sym
        object.public_method_defined?(symbol) || object.protected_method_defined?(symbol) || object.private_method_defined?(symbol)
      end
    end

    def verify_public_leaks(target_types, result)
      expected_names = target_types.keys.to_h { |name| [NameMapper.runtime_constant_path(name), true] }
      namespaces = expected_names.keys.flat_map do |name|
        parts = name.split("::")
        (1...parts.length).map { |length| parts.first(length).join("::") }
      end.to_h { |name| [name, true] }
      walk_namespace(Microsoft::Xna::Framework, "Microsoft::Xna::Framework") do |name, object|
        next if expected_names[name] || namespaces[name]
        result.add("INTERNAL_TYPE_LEAK", name) if object.is_a?(Module)
      end

      target_types.each do |name, type|
        object = resolve_ruby_type(type.fetch("rubyName"))
        allowed = type.fetch("members").flat_map { |member| ruby_projections(member) }.map { |value| value.split(":", 2).last.to_sym }.uniq
        allowed.concat(%i[eql? hash to_s dup clone inspect to_i name value])
        direct = object.public_instance_methods(false) + object.protected_instance_methods(false)
        (direct.uniq - allowed).each do |method_name|
          # A Ruby language-support identity is not an XNA identity, and it is admitted by rule
          # rather than by name: it may exist only on a type that also projects the CLR identity it
          # is derived from. `each` is permitted where `GetEnumerator` is projected and nowhere
          # else, so it can never quietly stand in for a missing XNA member.
          derived = CNA::Runtime::LanguageSupport.derived_from(method_name)
          next if derived && type.fetch("members").any? { |member| member["name"] == derived }

          result.add("UNEXPECTED_MEMBER", "#{name}::#{method_name} runtime", type: name)
        end
      end

      target.fetch("types").each do |type|
        type.fetch("members").each do |member|
          signature = JSON.generate(member)
          result.add("RAW_HANDLE_LEAK", "#{type["name"]}::#{member["name"]}") if signature.match?(/CNA_Handle|Fiddle::Pointer|void\*/)
          result.add("PUBLIC_NATIVE_FFI_LEAK", "#{type["name"]}::#{member["name"]}") if signature.match?(/CNA::Native|Fiddle/)
        end
      end

      mapping_signature = JSON.generate(target.fetch("languageTypeMappings", {}))
      result.add("RAW_HANDLE_LEAK", "language type mapping") if mapping_signature.match?(/CNA_Handle|Fiddle::Pointer|void\*/)
      result.add("PUBLIC_NATIVE_FFI_LEAK", "language type mapping") if mapping_signature.match?(/CNA::Native|Fiddle/)
    end

    def walk_namespace(object, prefix, &block)
      object.constants(false).each do |constant|
        child = object.const_get(constant, false)
        name = "#{prefix}::#{constant}"
        block.call(name, child)
        walk_namespace(child, name, &block) if child.instance_of?(Module)
      end
    end
  end
end
