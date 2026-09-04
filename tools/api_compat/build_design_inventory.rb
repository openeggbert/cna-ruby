# frozen_string_literal: true

# Derives the Microsoft-free audit table for the XNA `Design` converter family from the pinned
# original Microsoft.Xna.Framework.dll.
#
# The thirteen converters differ from each other in a handful of ways -- which members they declare,
# which value type they build, which members that type's descriptors name, in what order they are
# authored and in what order they are sorted, whether the descriptor reads a field or a property,
# what the scalar element type is, whether string conversion is supported, and which constructor an
# `InstanceDescriptor` is handed -- and every one of those is a contract a consumer can observe.
# Writing that table by hand is exactly the kind of transcription this project refuses, so it is
# derived here from the IL and `test/test_design_converters.rb` asserts the Ruby implementation
# against it. A mutation on either side is then a test failure rather than a discrepancy nobody
# reads.
#
# Nothing Microsoft-owned is written: the output records names, order, arities, type identities and
# derived facts, never IL text.

require "digest"
require "json"

FRAMEWORK = "Microsoft.Xna.Framework.dll"
FRAMEWORK_SHA256 = "38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130"

BASE = "Microsoft.Xna.Framework.Design.MathTypeConverter"
DERIVED = %w[
  BoundingBoxConverter BoundingSphereConverter ColorConverter MatrixConverter PlaneConverter
  PointConverter QuaternionConverter RayConverter RectangleConverter Vector2Converter
  Vector3Converter Vector4Converter
].map { |name| "Microsoft.Xna.Framework.Design.#{name}" }.freeze
# The three `private` descriptor implementations the converters build their collections out of.
# They are not XNA public surface and never become one; what the table records is the contract the
# public `GetProperties` answer carries.
DESCRIPTORS = %w[
  Microsoft.Xna.Framework.Design.MemberPropertyDescriptor
  Microsoft.Xna.Framework.Design.FieldPropertyDescriptor
  Microsoft.Xna.Framework.Design.PropertyPropertyDescriptor
].freeze

root = File.expand_path("../..", __dir__)
directory = ENV.fetch("XNA_REFERENCE_ASSEMBLIES") do
  abort "XNA_REFERENCE_ASSEMBLIES must name a directory holding the pinned XNA 4.0 Windows assemblies"
end
unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |entry| File.executable?(File.join(entry, "ikdasm")) }
  abort "ikdasm is required and was not found on PATH (Debian package: ikdasm)"
end

path = File.join(directory, FRAMEWORK)
abort "missing pinned assembly #{FRAMEWORK}" unless File.file?(path)
actual = Digest::SHA256.file(path).hexdigest
abort "SHA-256 mismatch for #{FRAMEWORK}: expected #{FRAMEWORK_SHA256}, got #{actual}" unless actual == FRAMEWORK_SHA256

il = IO.popen(["ikdasm", path], &:read)
abort "ikdasm produced no IL for #{FRAMEWORK}" if il.nil? || il.empty?

# ---------------------------------------------------------------------------------------------
# Slicing. `ikdasm` opens a type with `.class` at column zero and closes it with a matching
# `} // end of class <name>`, and a method the same way one indent in, so both are found by their
# own closing marker rather than by brace counting -- a `.try`/`catch` body has braces of its own.
# ---------------------------------------------------------------------------------------------

def type_body(il, identity)
  start = il.index(/^\.class .*\b#{Regexp.escape(identity)}\b/)
  return nil if start.nil?

  finish = il.index("\n} // end of class #{identity}\n", start)
  return nil if finish.nil?

  il[start...finish]
end

METHOD_OPEN = /^  \.method (.*?)$/.freeze

def methods_of(body)
  found = {}
  scanner = 0
  while (open = body.index(/^  \.method /, scanner))
    header_end = body.index(/\bcil managed\b|\bruntime managed\b/, open)
    break if header_end.nil?

    header = body[open...header_end].sub(/\A\s*\.method\s*/, "").gsub(/\s+/, " ").strip
    # A generic method is declared `ConvertToValues<T>(...)` and closed `::ConvertToValues`, so the
    # declared spelling is not the marker's. Reducing to the CLR definition name is what keeps the
    # close marker findable -- reading `<T>` as part of the name loses every method after it.
    name = header[/('[^']+'|[A-Za-z_.<>][A-Za-z0-9_.<>`]*)\s*\(/, 1].to_s.tr("'", "").sub(/<[^<>]*>\z/, "")
    close = body.index(/^  \} \/\/ end of method [^\n]*::#{Regexp.escape(name)}\n/, header_end)
    close = body.length if close.nil?
    (found[name] ||= []) << {"header" => header, "body" => body[header_end...close]}
    scanner = close + 1
  end
  found
end

LDC = {"ldc.i4.m1" => -1, "ldc.i4.0" => 0, "ldc.i4.1" => 1, "ldc.i4.2" => 2, "ldc.i4.3" => 3,
       "ldc.i4.4" => 4, "ldc.i4.5" => 5, "ldc.i4.6" => 6, "ldc.i4.7" => 7, "ldc.i4.8" => 8}.freeze

# One (opcode, operand) pair per instruction, with `ikdasm`'s wrapped multi-line operands folded
# back on. A call signature spans several lines, and reading only the first loses the parameter
# list that decides which constructor an InstanceDescriptor is handed.
def operations(text)
  ops = []
  text.to_s.each_line do |line|
    stripped = line.rstrip
    if (match = /^\s+IL_[0-9a-f]{4}:\s+(\S+)\s*(.*)$/.match(stripped))
      ops << [match[1], +match[2]]
    elsif !ops.empty? && !stripped.strip.empty? && !stripped.strip.start_with?(".", "}", "{", "//")
      ops.last[1] << " " << stripped.strip
    end
  end
  ops
end

def strings(ops) = ops.filter_map { |op, operand| operand[/\A"(.*)"\z/m, 1] if op == "ldstr" }

def constant(op, operand)
  return LDC[op] if LDC.key?(op)
  return Integer(operand.strip) if %w[ldc.i4 ldc.i4.s].include?(op) && operand.to_s.strip.match?(/\A-?\d+\z/)

  nil
end

# IL's short spellings for the primitive value types. A `ldtoken` writes `[mscorlib]System.Single`
# and a signature writes `float32` for the same identity, so a table that recorded both as written
# could not compare a constructor a converter *names* against one the reference contract declares.
PRIMITIVES = {
  "bool" => "System.Boolean", "char" => "System.Char", "float32" => "System.Single",
  "float64" => "System.Double", "int8" => "System.SByte", "int16" => "System.Int16",
  "int32" => "System.Int32", "int64" => "System.Int64", "object" => "System.Object",
  "string" => "System.String", "uint8" => "System.Byte", "uint16" => "System.UInt16",
  "uint32" => "System.UInt32", "uint64" => "System.UInt64", "void" => "System.Void"
}.freeze

# A CLR type spelling reduced to the identity this project addresses types by: the assembly
# reference prefix and any `valuetype`/`class` keyword are notation, not identity.
def identity(text)
  bare = text.to_s.strip.sub(/\A(?:valuetype|class)\s+/, "").sub(/\A\[[^\]]+\]/, "").strip
  PRIMITIVES.fetch(bare, bare)
end

def newobj_target(operand) = identity(operand[/void\s+(.*?)::\.ctor/m, 1].to_s)

# The declared parameter types of a `newobj`/`call` operand, split at the top level so a
# constructed generic argument list stays whole.
def signature_types(operand)
  inner = operand[/::\.ctor\s*\((.*)\)\s*\z/m, 1] || operand[/\((.*)\)\s*\z/m, 1]
  return [] if inner.nil?

  parts = []
  depth = 0
  buffer = +""
  inner.each_char do |char|
    case char
    when "<", "[", "(" then depth += 1
    when ">", "]", ")" then depth -= 1
    end
    if char == "," && depth.zero?
      parts << buffer
      buffer = +""
    else
      buffer << char
    end
  end
  parts << buffer
  parts.map { |part| identity(part.gsub(/\s+/, " ")) }.reject(&:empty?)
end

# ---------------------------------------------------------------------------------------------
# The facts, each read from the operand stream rather than assumed.
# ---------------------------------------------------------------------------------------------

# The descriptors a constructor authors, in the order it authors them. The shape is always
# `ldstr <member>; callvirt Type::GetField|GetProperty; newobj <descriptor class>`, so the member
# name is the `ldstr` immediately before the lookup and never a token bounded on one side only.
def authored_descriptors(ops)
  found = []
  ops.each_with_index do |(op, operand), index|
    next unless op == "callvirt"

    accessor = operand[/System\.Type::Get(Field|Property)\(string\)/, 1]
    next if accessor.nil?

    name = ops[0...index].reverse.find { |candidate_op, _| candidate_op == "ldstr" }&.last&.[](/\A"(.*)"\z/m, 1)
    descriptor = ops[index..].find { |candidate_op, _| candidate_op == "newobj" }&.last
    found << {"member" => name, "reflection" => accessor == "Field" ? "GetField" : "GetProperty",
              "descriptor" => newobj_target(descriptor.to_s).split(".").last}
  end
  found
end

# The `Sort(string[])` order, if the constructor sorts at all. The names are the `ldstr` run that
# fills the array handed to it, which is every string pushed after the `newarr System.String`.
def sort_order(ops)
  index = ops.index { |op, operand| op == "callvirt" && operand.include?("PropertyDescriptorCollection::Sort") }
  return nil if index.nil?

  array = ops[0...index].rindex { |op, operand| op == "newarr" && identity(operand) == "System.String" }
  return nil if array.nil?

  strings(ops[array...index])
end

def support_string_convert(ops)
  index = ops.rindex { |op, operand| op == "stfld" && operand.include?("::supportStringConvert") }
  # The base constructor sets it to true; a derived constructor that never stores it keeps that.
  return true if index.nil?

  value = ops[0...index].reverse.find { |op, operand| !constant(op, operand).nil? }
  constant(*value) == 1
end

def value_type(ops)
  ops.filter_map { |op, operand| identity(operand) if op == "ldtoken" }
     .find { |token| token.start_with?("Microsoft.Xna.Framework.") }
end

# What `ConvertFrom` does: the scalar element type it asks `ConvertToValues<T>` for, how many
# values it demands, the parameter names it names in the failure message, and the constructor it
# feeds. A converter that declares no `ConvertFrom` inherits `TypeConverter`'s.
def convert_from(ops)
  call = ops.find { |op, operand| op == "call" && operand.include?("MathTypeConverter::ConvertToValues<") }
  return nil if call.nil?

  index = ops.index(call)
  element = call.last[/ConvertToValues<([^>]*)>/, 1].to_s.strip
  array = ops[0...index].rindex { |op, operand| op == "newarr" && identity(operand) == "System.String" }
  count = ops[0...array].reverse.filter_map { |op, operand| constant(op, operand) }.first
  constructed = ops[index..].find { |op, _| op == "newobj" }&.last
  {"elementType" => element, "arrayCount" => count, "expectedParams" => strings(ops[array...index]),
   "constructs" => newobj_target(constructed.to_s), "constructorParameters" => signature_types(constructed.to_s)}
end

# What `ConvertTo` does. Two branches are observable: a string branch, present only when the
# converter supports string conversion, and an `InstanceDescriptor` branch, which names a
# constructor by its parameter types and hands it one argument per member read.
def convert_to(ops)
  join = ops.find { |op, operand| op == "call" && operand.include?("MathTypeConverter::ConvertFromValues<") }
  descriptor = ops.index { |op, operand| op == "newobj" && newobj_target(operand).end_with?("InstanceDescriptor") }
  facts = {"stringBranch" => !join.nil?,
           "instanceDescriptorBranch" => !descriptor.nil?,
           "elementType" => join&.last&.[](/ConvertFromValues<([^>]*)>/, 1)&.strip}
  if descriptor
    constructor = ops[0...descriptor].rindex { |op, operand| op == "call" && operand.include?("System.Type::GetConstructor") }
    array = ops[0...constructor].rindex { |op, operand| op == "newarr" && identity(operand) == "System.Type" }
    facts["constructorParameters"] =
      ops[array...constructor].filter_map { |op, operand| identity(operand) if op == "ldtoken" }
    # The arguments are the members read into the `object[]` between the constructor lookup and the
    # `newobj`. A value type's member is an `ldfld`; a class's would be a property call.
    facts["arguments"] = ops[constructor...descriptor].filter_map do |op, operand|
      next unless %w[ldfld call callvirt].include?(op)

      name = operand[/::(get_)?([A-Za-z_][A-Za-z0-9_]*)\s*(\(|\z)/, 2]
      name if op == "ldfld" || operand.include?("::get_")
    end
  end
  facts
end

# What `CreateInstance` does: the dictionary keys it reads, in order, and the constructor it feeds.
def create_instance(ops)
  keys = ops.each_with_index.filter_map do |(op, operand), index|
    next unless op == "callvirt" && operand.include?("IDictionary::get_Item")

    ops[0...index].reverse.find { |candidate, _| candidate == "ldstr" }&.last&.[](/\A"(.*)"\z/m, 1)
  end
  constructed = ops.reverse.find { |op, _| op == "newobj" }&.last
  {"keys" => keys, "constructs" => newobj_target(constructed.to_s),
   "constructorParameters" => signature_types(constructed.to_s),
   "nullCheck" => ops.any? { |op, operand| op == "newobj" && operand.include?("ArgumentNullException") }}
end

# A member whose whole body is "push the arguments and call the base implementation" is declared
# but adds nothing: BoundingBoxConverter.ConvertFrom is one. Recording it is what keeps the Ruby
# projection from inventing behaviour for a member XNA declares as a pure forward.
def pure_forward(ops)
  calls = ops.select { |op, _| %w[call callvirt newobj].include?(op) }
  return nil unless calls.length == 1 && ops.last.first == "ret"
  return nil unless ops.none? { |op, _| op.start_with?("br", "switch", "leave") }

  target = calls.first.last[/([A-Za-z_][A-Za-z0-9_.`]*)::([A-Za-z_][A-Za-z0-9_]*)/m, 0]
  identity(target.to_s)
end

# ---------------------------------------------------------------------------------------------
# The table.
# ---------------------------------------------------------------------------------------------

def declared_members(methods)
  methods.flat_map do |name, overloads|
    overloads.map do |overload|
      access = %w[public family private assembly famorassem famandassem]
               .find { |token| overload.fetch("header").split(/\s+/).include?(token) } || "public"
      {"name" => name, "access" => access, "virtual" => overload.fetch("header").include?(" virtual "),
       "static" => !overload.fetch("header").include?(" instance ")}
    end
  end
end

base_body = type_body(il, BASE) or abort "#{BASE} not found in the pinned IL"
base_methods = methods_of(base_body)
base_record = {
  "type" => BASE,
  "baseType" => identity(base_body[/^\.class[^\n]*\n\s*extends\s+([^\n]+)/, 1].to_s),
  "fields" => base_body.scan(/^\s*\.field\s+(\S+)\s+(.+?)\s+(\S+)\s*$/).map do |access, type, name|
    {"name" => name, "access" => access, "type" => identity(type)}
  end,
  "members" => declared_members(base_methods),
  "supportStringConvertDefault" => support_string_convert(operations(base_methods.fetch(".ctor").first.fetch("body"))),
  # The two fallbacks that make half of each answer the base class's rather than this type's.
  "canConvertFromFallback" =>
    identity(operations(base_methods.fetch("CanConvertFrom").first.fetch("body"))
      .filter_map { |op, operand| operand[/([A-Za-z_][A-Za-z0-9_.]*::CanConvertFrom)/m, 1] if op == "call" }.first.to_s),
  "canConvertToFallback" =>
    identity(operations(base_methods.fetch("CanConvertTo").first.fetch("body"))
      .filter_map { |op, operand| operand[/([A-Za-z_][A-Za-z0-9_.]*::CanConvertTo)/m, 1] if op == "call" }.first.to_s),
  "canConvertToSpecialCase" =>
    operations(base_methods.fetch("CanConvertTo").first.fetch("body"))
      .filter_map { |op, operand| identity(operand) if op == "ldtoken" }.first,
  "canConvertFromSpecialCase" =>
    operations(base_methods.fetch("CanConvertFrom").first.fetch("body"))
      .filter_map { |op, operand| identity(operand) if op == "ldtoken" }.first,
  "getPropertiesReadsField" =>
    operations(base_methods.fetch("GetProperties").first.fetch("body"))
      .filter_map { |op, operand| operand.split("::").last&.strip if op == "ldfld" }.first,
  "getCreateInstanceSupported" =>
    constant(*operations(base_methods.fetch("GetCreateInstanceSupported").first.fetch("body")).first) == 1,
  "getPropertiesSupported" =>
    constant(*operations(base_methods.fetch("GetPropertiesSupported").first.fetch("body")).first) == 1
}

descriptors = DESCRIPTORS.map do |name|
  body = type_body(il, name) or abort "#{name} not found in the pinned IL"
  methods = methods_of(body)
  record = {
    "type" => name,
    "baseType" => identity(body[/^\.class[^\n]*\n\s*extends\s+([^\n]+)/, 1].to_s),
    "abstract" => body[/^\.class[^\n]*/].to_s.include?(" abstract "),
    "members" => declared_members(methods),
    "behaviour" => {}
  }
  methods.each do |member, overloads|
    ops = operations(overloads.first.fetch("body"))
    next if ops.empty?

    constant_answer = ops.length == 2 && ops.last.first == "ret" ? constant(*ops.first) : nil
    record["behaviour"][member] = {
      "constantAnswer" => constant_answer,
      "empty" => ops.length == 1 && ops.first.first == "ret",
      "reads" => ops.filter_map { |op, operand| operand.split("::").last&.strip if op == "ldfld" }.uniq,
      "calls" => ops.filter_map { |op, operand| identity(operand[/([A-Za-z_][A-Za-z0-9_.`]*::[A-Za-z_][A-Za-z0-9_]*)/m, 1].to_s) if %w[call callvirt].include?(op) }.uniq
    }.compact
  end
  record
end

# The public constructors the reference contract declares for each XNA value type, which is what
# `Type.GetConstructor(Type[])` resolves against: default binding finds public instance
# constructors and nothing else.
reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
REFERENCE_CONSTRUCTORS = reference.fetch("types").to_h do |type|
  signatures = type.fetch("members").select { |member| member["kind"] == "constructor" && member["access"] == "public" }
                   .map { |member| member.fetch("parameters", []).map { |parameter| parameter.fetch("type") } }
  [type.fetch("name"), signatures]
end.freeze

converters = DERIVED.map do |name|
  body = type_body(il, name) or abort "#{name} not found in the pinned IL"
  methods = methods_of(body)
  constructor = operations(methods.fetch(".ctor").first.fetch("body"))
  record = {
    "type" => name,
    "baseType" => identity(body[/^\.class[^\n]*\n\s*extends\s+([^\n]+)/, 1].to_s),
    "valueType" => value_type(constructor),
    "declaredMembers" => declared_members(methods),
    "supportStringConvert" => support_string_convert(constructor),
    "descriptors" => authored_descriptors(constructor),
    "sortOrder" => sort_order(constructor)
  }
  record["convertFrom"] = methods.key?("ConvertFrom") ? convert_from(operations(methods.fetch("ConvertFrom").first.fetch("body"))) : nil
  record["convertFromForwardsTo"] = methods.key?("ConvertFrom") ? pure_forward(operations(methods.fetch("ConvertFrom").first.fetch("body"))) : nil
  record["convertTo"] = methods.key?("ConvertTo") ? convert_to(operations(methods.fetch("ConvertTo").first.fetch("body"))) : nil
  record["createInstance"] = methods.key?("CreateInstance") ? create_instance(operations(methods.fetch("CreateInstance").first.fetch("body"))) : nil
  # The order a consumer actually receives from GetProperties: the sorted order when the
  # constructor sorts, and the authored order when it does not.
  record["propertyOrder"] = record.fetch("sortOrder") || record.fetch("descriptors").map { |entry| entry.fetch("member") }
  # Whether the constructor the InstanceDescriptor branch names actually exists. `GetConstructor`
  # answers **null** for a signature no public constructor matches, and the IL immediately tests
  # that with `op_Inequality(ctor, null)` -- so a converter naming a constructor its value type
  # does not declare skips the branch entirely and falls through to the base. That is a real,
  # observable answer, and resolving the name against the reference contract is the only way to
  # know which converters take it.
  branch = record.dig("convertTo", "constructorParameters")
  if branch
    declared = REFERENCE_CONSTRUCTORS.fetch(record.fetch("valueType"), [])
    record["convertTo"]["constructorResolves"] = declared.include?(branch)
    record["convertTo"]["declaredConstructors"] = declared
    record["convertTo"]["instanceDescriptorAnswer"] =
      record["convertTo"]["constructorResolves"] ? "InstanceDescriptor" : "falls through to TypeConverter.ConvertTo"
  end
  record
end

# The BCL identities the family reaches, counted rather than remembered. This is the demand set the
# BCL inventory's ComponentModel families have to satisfy, so it is derived from the same IL the
# converters are.
reached = (([BASE] + DERIVED + DESCRIPTORS).flat_map do |name|
  body = type_body(il, name).to_s
  body.scan(/\[(mscorlib|System)\]([A-Za-z_][A-Za-z0-9_.`+]*)/).map { |assembly, type| "#{assembly}:#{type}" }
end).tally.sort_by { |identity, count| [-count, identity] }.to_h

inventory = {
  "schemaVersion" => 1,
  "authority" => "the pinned original Microsoft.Xna.Framework.dll, admitted by exact SHA-256",
  "provenance" => "derived with ikdasm. No Microsoft-owned bytes, IL text or machine-local path is reproduced here.",
  "scope" => "the thirteen Microsoft.Xna.Framework.Design converters and the three private PropertyDescriptor implementations their collections are built from",
  "assembly" => {"name" => FRAMEWORK, "sha256" => FRAMEWORK_SHA256, "bytes" => File.size(path)},
  "DESIGN_TYPES" => 1 + DERIVED.length,
  "DESIGN_DESCRIPTOR_TYPES" => DESCRIPTORS.length,
  "DESIGN_IDENTITIES" => base_record.fetch("members").length + base_record.fetch("fields").length +
    converters.sum { |converter| converter.fetch("declaredMembers").length },
  "DESIGN_REACHED_BCL_IDENTITIES" => reached.length,
  "base" => base_record,
  "descriptors" => descriptors,
  "converters" => converters,
  "reachedBclIdentities" => reached
}

File.write(File.join(root, "docs", "generated", "design-converter-inventory.json"), JSON.pretty_generate(inventory) + "\n")

puts "DESIGN_TYPES=#{inventory.fetch("DESIGN_TYPES")}"
puts "DESIGN_DESCRIPTOR_TYPES=#{inventory.fetch("DESIGN_DESCRIPTOR_TYPES")}"
puts "DESIGN_IDENTITIES=#{inventory.fetch("DESIGN_IDENTITIES")}"
puts "DESIGN_REACHED_BCL_IDENTITIES=#{inventory.fetch("DESIGN_REACHED_BCL_IDENTITIES")}"
