# frozen_string_literal: true

# Derives the Microsoft-free BCL inventory from the pinned Microsoft .NET Framework 4.0 mscorlib.
#
# This is a **separate authority** from the XNA reference contract. mscorlib is not an XNA assembly
# and none of its types is an XNA identity, so nothing it carries may enter REFERENCE_TYPES /
# REFERENCE_MEMBERS or the XNA IL inventory. It exists for one reason: several XNA public members
# name a BCL type, and this binding refuses to project a BCL type from memory.
#
# Point BCL_REFERENCE_ASSEMBLIES at a directory holding mscorlib.dll and XNA_REFERENCE_ASSEMBLIES
# at the pinned XNA assemblies. Admission is by exact SHA-256, never by filename, and the pairing
# between the two authorities is proved rather than assumed: every pinned XNA assembly records an
# AssemblyRef to mscorlib, and that reference's name, version and public key token must equal the
# identity the admitted binary carries. The public key token is *derived* from the assembly's own
# .publickey blob (SHA-1, last eight bytes, reversed) rather than trusted from a constant.
#
# The inventory is demand-driven. A family is admitted only when the XNA reference contract really
# names it; a family with no XNA consumer is refused, which is what keeps this from becoming a
# reimplementation of the .NET Framework. Nothing Microsoft-owned is written: the output records
# identities, shapes and derived behavioural facts, never IL text and never a machine-local path.

require "digest"
require "json"

MSCORLIB = {
  "sha256" => "5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63",
  "bytes" => 5196112,
  "assemblyName" => "mscorlib",
  "assemblyVersion" => "4.0.0.0",
  "fileVersion" => "4.0.30319.1",
  "publicKeyToken" => "b77a5c561934e089",
  "company" => "Microsoft Corporation",
  "description" => "Microsoft Common Language Runtime Class Library"
}.freeze

XNA_PINNED = %w[
  Microsoft.Xna.Framework.dll Microsoft.Xna.Framework.Graphics.dll Microsoft.Xna.Framework.Game.dll
  Microsoft.Xna.Framework.Input.Touch.dll Microsoft.Xna.Framework.Xact.dll
  Microsoft.Xna.Framework.Storage.dll Microsoft.Xna.Framework.Video.dll
  Microsoft.Xna.Framework.Net.dll Microsoft.Xna.Framework.GamerServices.dll
  Microsoft.Xna.Framework.Avatar.dll
].freeze

# The BCL families this binding is allowed to inventory, and why each is here. Every entry must be
# named by the XNA reference contract; the tool proves that below and aborts otherwise.
FAMILIES = {
  "System.Collections.ObjectModel.ReadOnlyCollection`1" =>
    "the CLR base of four XNA collection types and the declared return type of six XNA members",
  "System.Collections.ObjectModel.Collection`1" =>
    "the CLR base of GameComponentCollection, and the mutable sibling ReadOnlyCollection`1 is measured against",
  "System.Collections.Generic.Dictionary`2" =>
    "the CLR base of LaunchParameters, the one dependency-complete XNA type blocked on it alone"
}.freeze

# Support enums the collection families throw through. Their literal names are what make a derived
# throw fact readable; they are internal CLR plumbing, not surface.
SUPPORT_ENUMS = %w[System.ExceptionResource System.ExceptionArgument].freeze
THROW_HELPER = "System.ThrowHelper"

root = File.expand_path("../..", __dir__)
bcl_directory = ENV.fetch("BCL_REFERENCE_ASSEMBLIES") do
  abort "BCL_REFERENCE_ASSEMBLIES must name a directory holding the pinned Microsoft .NET Framework mscorlib.dll"
end
xna_directory = ENV.fetch("XNA_REFERENCE_ASSEMBLIES") do
  abort "XNA_REFERENCE_ASSEMBLIES must name a directory holding the pinned XNA 4.0 Windows assemblies"
end
unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |entry| File.executable?(File.join(entry, "ikdasm")) }
  abort "ikdasm is required and was not found on PATH (Debian package: ikdasm)"
end

mscorlib_path = File.join(bcl_directory, "mscorlib.dll")
abort "missing pinned mscorlib.dll" unless File.file?(mscorlib_path)
actual_sha = Digest::SHA256.file(mscorlib_path).hexdigest
unless actual_sha == MSCORLIB.fetch("sha256")
  abort "SHA-256 mismatch for mscorlib.dll: expected #{MSCORLIB.fetch("sha256")}, got #{actual_sha}"
end
unless File.size(mscorlib_path) == MSCORLIB.fetch("bytes")
  abort "byte-length mismatch for mscorlib.dll"
end

# ---------------------------------------------------------------------------------------------
# Identity, derived from the binary rather than asserted.
# ---------------------------------------------------------------------------------------------

il = IO.popen(["ikdasm", mscorlib_path], &:read)
abort "ikdasm produced no IL for mscorlib.dll" if il.nil? || il.empty?

manifest = il[/^\.assembly #{Regexp.escape(MSCORLIB.fetch("assemblyName"))}\b.*?^\}/m]
abort "no .assembly mscorlib manifest in the disassembly" if manifest.nil?
public_key = manifest[/^\s*\.publickey\s*=\s*\(([0-9A-Fa-f\s]*)\)/m, 1]
abort "no .publickey in the mscorlib manifest" if public_key.nil?
version = manifest[/^\s*\.ver\s+(\d+):(\d+):(\d+):(\d+)/, 0].to_s.sub(/\A\s*\.ver\s+/, "").tr(":", ".")
# The CLR derives a public key token as the low eight bytes of the key's SHA-1, reversed. Deriving
# it here is the point: the expected token is a conclusion drawn from the admitted bytes, never a
# constant this tool trusts.
derived_token = Digest::SHA1.digest([public_key.gsub(/\s+/, "")].pack("H*")).bytes.last(8).reverse
                      .map { |byte| format("%02x", byte) }.join
unless derived_token == MSCORLIB.fetch("publicKeyToken")
  abort "public key token mismatch: derived #{derived_token}, expected #{MSCORLIB.fetch("publicKeyToken")}"
end
unless version == MSCORLIB.fetch("assemblyVersion")
  abort "assembly version mismatch: found #{version}, expected #{MSCORLIB.fetch("assemblyVersion")}"
end

# The PE version resource carries the Microsoft origin claim. Read it straight out of the file.
def version_resource(bytes, key)
  needle = key.encode("UTF-16LE").b
  index = bytes.index(needle)
  return nil if index.nil?

  cursor = index + needle.bytesize
  cursor += 2 while bytes.byteslice(cursor, 2) == "\x00\x00".b
  out = +""
  while (unit = bytes.byteslice(cursor, 2)) && unit != "\x00\x00".b && unit.bytesize == 2
    out << unit
    cursor += 2
  end
  out.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
end

pe = File.binread(mscorlib_path)
%w[CompanyName FileDescription].zip(%w[company description]).each do |resource, key|
  found = version_resource(pe, resource)
  abort "#{resource} mismatch: found #{found.inspect}" unless found == MSCORLIB.fetch(key)
end
file_version = version_resource(pe, "FileVersion").to_s
unless file_version.start_with?(MSCORLIB.fetch("fileVersion"))
  abort "FileVersion mismatch: found #{file_version.inspect}"
end

# The pairing proof: this is the mscorlib identity the pinned XNA assemblies bind to.
pairing = XNA_PINNED.map do |name|
  path = File.join(xna_directory, name)
  abort "missing pinned XNA assembly #{name}" unless File.file?(path)
  table = IO.popen(["ikdasm", "--assemblyref", path], &:read).to_s
  entry = table.split(/^\d+: /).find { |chunk| chunk.include?("Name=#{MSCORLIB.fetch("assemblyName")}\n") }
  abort "#{name} declares no AssemblyRef to mscorlib" if entry.nil?
  ref_version = entry[/Version=([0-9.]+)/, 1]
  ref_token = entry[/Public Key:\n0x00000000:\s*((?:[0-9A-Fa-f]{2}\s+){8})/, 1].to_s.split.map(&:downcase).join
  unless ref_version == version && ref_token == derived_token
    abort "#{name} binds mscorlib #{ref_version}/#{ref_token}, not #{version}/#{derived_token}"
  end

  {"assembly" => name, "referencedVersion" => ref_version, "referencedPublicKeyToken" => ref_token}
end

# ---------------------------------------------------------------------------------------------
# Demand: which XNA reference identities name each family.
# ---------------------------------------------------------------------------------------------

reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
consumers = FAMILIES.keys.to_h { |family| [family, []] }
reference.fetch("types").each do |type|
  name = type.fetch("name")
  FAMILIES.each_key do |family|
    consumers[family] << "#{name} (base)" if type["baseType"].to_s.start_with?(family)
    type.fetch("members").each do |member|
      signatures = [member["type"], member["returnType"], *member.fetch("parameters", []).map { |p| p["type"] }]
      next unless signatures.compact.any? { |signature| signature.include?(family) }

      consumers[family] << "#{name}::#{member.fetch("name")}"
    end
  end
end
consumers.each do |family, list|
  list.uniq!
  list.sort!
  abort "family #{family} has no XNA consumer; the inventory is demand-driven" if list.empty?
end

# ---------------------------------------------------------------------------------------------
# IL extraction. Nested- and generic-aware, following the same conventions as the XNA inventory:
# a nested type is addressed Parent+Child, and a generic type keeps its CLR `N spelling.
# ---------------------------------------------------------------------------------------------

GENERIC_SUFFIX = /<[^<>]*>\z/.freeze
METHOD_NAME = /('[^']+'|[A-Za-z_.<>][A-Za-z0-9_.<>`]*)\s*\(/.freeze

def type_bodies(il)
  bodies = {}
  open = []
  il.each_line do |line|
    stripped = line.rstrip
    indent = line[/\A */].length
    leading = stripped.lstrip
    if leading.start_with?(".class ") && !leading.start_with?(".class extern")
      short = stripped.split(/\s+/).last.to_s.tr("'", "").sub(GENERIC_SUFFIX, "")
      open.pop while !open.empty? && open.last[:indent] >= indent
      open << {name: open.empty? ? short : "#{open.last[:name]}+#{short}", short: short,
               header: +"#{leading}\n", body: +"", indent: indent, declaring: open.last&.fetch(:name)}
      next
    end
    next if open.empty?

    if leading.start_with?("} // end of class ") && indent == open.last[:indent] &&
       leading.sub("} // end of class ", "").tr("'", "").sub(GENERIC_SUFFIX, "") == open.last[:short]
      frame = open.pop
      bodies[frame[:name]] = frame
      next
    end
    # Everything between the `.class` line and its opening brace is the declaration: `extends`,
    # `implements` and every continuation line of a multi-interface list.
    if !open.last[:header].include?("{")
      open.last[:header] << "#{leading}\n"
      next
    end
    open.last[:body] << line
  end
  bodies
end

LDC = {
  "ldc.i4.m1" => -1, "ldc.i4.0" => 0, "ldc.i4.1" => 1, "ldc.i4.2" => 2, "ldc.i4.3" => 3,
  "ldc.i4.4" => 4, "ldc.i4.5" => 5, "ldc.i4.6" => 6, "ldc.i4.7" => 7, "ldc.i4.8" => 8
}.freeze

def constant(op, operand)
  return LDC[op] if LDC.key?(op)
  return Integer(operand.strip) if %w[ldc.i4 ldc.i4.s].include?(op) && operand.to_s.strip.match?(/\A-?\d+\z/)

  nil
end

# Splits a type body into its `.method`, `.field` and `.property` declarations. Every member keeps
# the raw operand stream only long enough to derive facts from it; none of it is written out.
def members(body)
  found = []
  header = nil
  current = nil
  depth = 0
  body.each_line do |line|
    stripped = line.rstrip
    leading = stripped.lstrip
    indent = line[/\A */].length

    if current && current[:kind] == "property"
      # `ikdasm` wraps a `.property` whose type is long onto a second line, leaving the property
      # name there rather than on the `.property` line. Reading only the first line names it "".
      if current[:name].empty? && !leading.start_with?("{", "}", ".")
        current[:declaration] = "#{current[:declaration]} #{leading}"
        current[:name] = current[:declaration][/([A-Za-z_.<>'][^(\s]*)\s*\(/, 1].to_s.tr("'", "")
        next
      end
      # A `.property` block declares nothing but its accessors, and their accessibility is the
      # property's: a CLR property whose getter is public is a public property.
      if leading.start_with?("{")
        depth += 1
      elsif leading.start_with?("}")
        depth -= 1
        if depth <= 0
          found << current
          current = nil
        end
      elsif leading.start_with?(".get ", ".set ", ".other ")
        current[:accessors] << {"accessor" => leading.split(" ", 2).first.delete("."),
                                "method" => call_target(leading)}
      end
      next
    end
    if current
      # `ikdasm` closes a method with `} // end of method Type::Name`, never a bare brace, so the
      # nesting depth of `.try`/`catch`/`finally` blocks is what decides where the body ends.
      if leading.start_with?("{")
        depth += 1
      elsif leading.start_with?("}")
        depth -= 1
        if depth <= 0
          found << current
          current = nil
        end
      elsif (match = /^\s+IL_[0-9a-f]{4}:\s+(\S+)\s*(.*)$/.match(stripped))
        current[:ops] << [match[1], +match[2]]
      elsif !current[:ops].empty? && !leading.empty? && !leading.start_with?(".")
        # `ikdasm` wraps a long operand -- a multi-parameter call signature, a switch table -- onto
        # continuation lines. Reading only the first line loses half of a two-argument throw helper
        # signature, so continuations are folded back onto the operand they belong to.
        current[:ops].last[1] << " " << leading
      end
      next
    end
    if header
      header[:text] << " " << leading
      if header[:text].match?(/\bcil managed\b|\bruntime managed\b/) || leading.end_with?("{")
        current = finish_header(header)
        depth = leading.end_with?("{") ? 1 : 0
        header = nil
      end
      next
    end
    if leading.start_with?(".method ")
      header = {kind: "method", text: +leading.sub(".method ", ""), indent: indent}
      next
    end
    if leading.start_with?(".field ")
      found << field_member(leading)
      next
    end
    next unless leading.start_with?(".property ")

    current = {kind: "property", name: leading[/([A-Za-z_.<>'][^(\s]*)\s*\(/, 1].to_s.tr("'", ""),
               declaration: leading.sub(".property ", ""), static: !leading.include?(" instance "),
               accessors: [], ops: []}
    depth = 0
  end
  found
end

def finish_header(header)
  text = header[:text].gsub(/pinvokeimpl\s*\([^)]*\)/, " ").gsub(/marshal\s*\([^)]*\)/, " ")
  match = METHOD_NAME.match(text)
  name = match ? match[1].tr("'", "") : "?"
  before = match ? text[0...match.begin(1)] : text
  after = match ? text[match.end(1)..] : ""
  parameters = after[/\((.*)\)\s*(?:cil|runtime)\s+managed/m, 1] || after[/\((.*)\)/m, 1] || ""
  flags = before.split(/\s+/)
  access = %w[public family private assembly famorassem famandassem].find { |token| flags.include?(token) } || "public"
  {kind: name == ".ctor" || name == ".cctor" ? "constructor" : "method",
   name: name,
   access: access,
   static: !flags.include?("instance"),
   abstract: flags.include?("abstract"),
   virtual: flags.include?("virtual"),
   returnType: return_type(before),
   parameters: split_parameters(parameters),
   ops: []}
end

MODIFIERS = %w[
  public family private assembly famorassem famandassem hidebysig newslot virtual final abstract
  specialname rtspecialname instance static cil managed runtime pinvokeimpl reqsecobj strict
].freeze

def return_type(before)
  tokens = before.split(/\s+/).reject(&:empty?)
  tokens = tokens.drop_while { |token| MODIFIERS.include?(token) }
  tokens.join(" ").strip
end

def split_parameters(text)
  return [] if text.nil? || text.strip.empty?

  parts = []
  depth = 0
  buffer = +""
  text.each_char do |char|
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
  parts.map { |part| part.strip.gsub(/\s+/, " ") }.reject(&:empty?).map do |part|
    tokens = part.split(" ")
    name = tokens.length > 1 ? tokens.last.tr("'", "") : nil
    type = tokens.length > 1 ? tokens[0..-2].join(" ") : part
    {"type" => type, "name" => name}
  end
end

def field_member(leading)
  declaration = leading.sub(".field ", "").sub(/\s*$/, "")
  tokens = declaration.split(/\s+/)
  access = %w[public family private assembly famorassem famandassem].find { |token| tokens.include?(token) } || "public"
  {kind: "field", name: tokens.last.to_s.tr("'", ""), access: access,
   static: tokens.include?("static"), declaration: declaration, ops: []}
end

bodies = type_bodies(il)

BRANCHES = /\A(?:br|brtrue|brfalse|beq|bge|bgt|ble|blt|bne|switch|leave)/.freeze

# A constructed generic operand -- `class System.Collections.Generic.ICollection`1<!T>::get_Count()`
# -- defeats a plain Type::Method regex, which happily matches the `T>` at the end of the argument
# list instead of the declaring type. Removing the balanced generic argument lists first leaves the
# CLR definition spelling the rest of this binding uses.
def strip_generic_arguments(text)
  out = +""
  depth = 0
  text.to_s.each_char do |char|
    case char
    when "<" then depth += 1
    when ">" then depth -= 1 if depth.positive?
    else out << char if depth.zero?
    end
  end
  out
end

def call_target(operand)
  match = /(?:\[[^\]]+\])?([A-Za-z_][A-Za-z0-9_.`+'\/]*)::([A-Za-z_.<>'][A-Za-z0-9_.<>`]*)/
          .match(strip_generic_arguments(operand))
  match && "#{match[1].tr("'", "").tr("/", "+")}::#{match[2].tr("'", "")}"
end

# Support tables, all derived. ExceptionResource / ExceptionArgument turn a bare `ldc.i4.s 28` into
# the literal `NotSupported_ReadOnlyCollection`; ThrowHelper turns a `call ThrowNotSupportedException`
# into the exception identity it actually constructs.
support_literals = SUPPORT_ENUMS.to_h do |enum|
  frame = bodies.fetch(enum) { abort "#{enum} not found in mscorlib IL" }
  literals = {}
  frame[:body].each_line do |line|
    match = /\.field public static literal valuetype #{Regexp.escape(enum)} ('[^']+'|\S+) = int32\(0x([0-9A-Fa-f]+)\)/.match(line)
    literals[Integer(match[2], 16)] = match[1].tr("'", "") if match
  end
  [enum, literals]
end

throw_helper = {}
helper_edges = {}
helper_frame = bodies.fetch(THROW_HELPER) { abort "#{THROW_HELPER} not found in mscorlib IL" }
members(helper_frame[:body]).each do |member|
  next unless member[:kind] == "method"

  # A generic helper is declared `Name<T>` and called `Name<!!0>`; both reduce to `Name`.
  helper_name = strip_generic_arguments(member[:name])
  exception = member[:ops].filter_map do |op, operand|
    operand[/\A\s*instance void ([A-Za-z_][A-Za-z0-9_.`]*Exception)::\.ctor/, 1] if op == "newobj"
  end.first
  if exception
    throw_helper[helper_name] = exception
    next
  end
  # A guard helper such as IfNullAndNullsAreIllegalThenThrow constructs nothing itself; it forwards
  # to the helper that does. Resolving through that edge is what keeps a derived throw fact from
  # falling back on the helper's name.
  forwarded = member[:ops].filter_map do |op, operand|
    next unless op == "call"

    target = call_target(operand)
    target.split("::").last if target&.start_with?("#{THROW_HELPER}::")
  end
  helper_edges[helper_name] = forwarded.uniq unless forwarded.empty?
end
loop do
  added = false
  helper_edges.each do |helper, targets|
    next if throw_helper.key?(helper)

    resolved = targets.filter_map { |target| throw_helper[target] }.uniq
    next unless resolved.length == 1

    throw_helper[helper] = resolved.first
    added = true
  end
  break unless added
end

# ---------------------------------------------------------------------------------------------
# Derived behavioural facts. Never IL text: what a member delegates to, what it throws, and
# whether the throw is unconditional.
# ---------------------------------------------------------------------------------------------


def behaviour(member, throw_helper, support_literals)
  ops = member[:ops]
  return nil if ops.empty?

  throws = []
  pending = []
  ops.each do |op, operand|
    value = constant(op, operand)
    # A throw helper's arguments are the constants pushed immediately before the call. Anything
    # else in between -- a comparison operand, a field read -- ends the window, so an unrelated
    # `ldc.i4.0` from a bounds test can never be read as an ExceptionResource.
    pending.clear if value.nil? && !%w[call callvirt newobj].include?(op)
    pending << value unless value.nil?
    if op == "newobj" && (exception = operand[/\A\s*instance void ([A-Za-z_][A-Za-z0-9_.`]*Exception)::\.ctor/, 1])
      throws << {"exception" => exception, "via" => "newobj"}
      pending.clear
      next
    end
    next unless op == "call" || op == "callvirt"

    target = call_target(operand)
    next unless target&.start_with?("System.ThrowHelper::")

    helper = target.split("::").last
    resource = nil
    argument = nil
    if operand.include?("System.ExceptionResource")
      resource = support_literals.fetch("System.ExceptionResource")[pending.last]
      argument = support_literals.fetch("System.ExceptionArgument")[pending[-2]] if operand.scan("valuetype").length > 1
    elsif operand.include?("System.ExceptionArgument")
      argument = support_literals.fetch("System.ExceptionArgument")[pending.last]
    end
    throws << {"exception" => throw_helper.fetch(helper, "unresolved:#{helper}"), "via" => "System.ThrowHelper::#{helper}",
               "resource" => resource, "argument" => argument}.compact
    pending.clear
  end

  opcodes = ops.map(&:first)
  facts = {}
  facts["throws"] = throws unless throws.empty?
  facts["throwsUnconditionally"] = true if !throws.empty? && opcodes.none? { |op| BRANCHES.match?(op) }
  # A pure forward: load self, read one instance field, push the arguments in order, make one call,
  # return. This is the shape that decides whether a wrapper is a view or a snapshot.
  field = ops.find { |op, _| op == "ldfld" }&.last
  calls = ops.select { |op, _| %w[call callvirt].include?(op) }
  if field && calls.length == 1 && throws.empty? && opcodes.none? { |op| BRANCHES.match?(op) } &&
     opcodes.first == "ldarg.0" && opcodes.last == "ret" &&
     opcodes.all? { |op| op.start_with?("ldarg", "ldfld", "call", "ret", "ldc.i4") }
    facts["delegatesTo"] = call_target(calls.first.last)
    facts["viaField"] = field.to_s.split("::").last.to_s.strip
  end
  facts["storesConstructorArgumentToField"] = ops.any? { |op, _| op == "stfld" } if member[:kind] == "constructor"
  facts.empty? ? nil : facts
end

ACCESS_RANK = {"public" => 3, "family" => 2, "famorassem" => 1}.freeze

# A `.property` declaration carries no accessibility of its own; the CLR reads it from the accessor
# methods. Resolving it here is what lets a property be filtered by the same surface rule as
# everything else instead of being silently dropped.
def annotate_properties(list)
  by_name = list.select { |member| member[:kind] == "method" }.to_h { |member| [member[:name], member] }
  list.each do |member|
    next unless member[:kind] == "property"

    accessors = member[:accessors].filter_map { |entry| by_name[entry.fetch("method").to_s.split("::").last] }
    member[:access] = accessors.map { |accessor| accessor[:access] }
                               .max_by { |access| ACCESS_RANK.fetch(access, 0) } || "private"
  end
  list
end

def surface?(member)
  return true if %w[public family].include?(member[:access].to_s)
  # An explicit interface implementation is IL-private and still observable through the interface.
  # For a read-only collection that is precisely where the refusal to mutate lives.
  member[:kind] == "method" && member[:name].to_s.include?(".")
end

def split_top_level(text)
  parts = []
  buffer = +""
  depth = 0
  text.to_s.each_char do |char|
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
  parts
end

def declaration_of(frame)
  header = frame[:header]
  # `implements` is a comma-separated list, but a constructed generic carries commas of its own:
  # `IDictionary`2<!TKey,!TValue>` is one entry, not two. Splitting only at depth zero is what keeps
  # `!TValue` from being recorded as an interface.
  declared = split_top_level(header[/implements\s+(.*?)\n\{/m, 1].to_s)
                .map { |item| item.strip.gsub(/\s+/, " ") }.reject(&:empty?)
  {"kind" => header.include?(" interface ") ? "interface" : header.include?("extends System.Enum") ? "enum" : "class",
   "baseType" => header[/extends\s+([^\n]+)/, 1]&.strip&.sub(/\s*implements.*/, ""),
   # As declared, so the element projection `<!T>` stays visible, and reduced to the CLR generic
   # definition spelling this binding addresses types by.
   "interfaceDeclarations" => declared,
   "interfaces" => declared.map { |item| strip_generic_arguments(item).sub(/\Aclass\s+/, "").strip },
   "genericParameters" => header[/`(\d+)</, 1]&.to_i || 0,
   "sealed" => header.include?(" sealed "),
   "abstract" => header.include?(" abstract ")}
end

selected = {}
# A public nested type of an admitted family is part of that family's observable surface: the
# enumerator a caller receives from GetEnumerator is reachable from the family's public members.
nested = FAMILIES.keys.flat_map do |family|
  bodies.keys.select do |identity|
    identity.start_with?("#{family}+") &&
      (bodies.fetch(identity)[:header].include?(" nested public ") || bodies.fetch(identity)[:header].include?(" public "))
  end
end
queue = FAMILIES.keys + nested.sort
# The exception closure stops at System.Exception, which is where this binding's projection register
# already roots: System.Exception maps to StandardError, so walking into System.Object would record
# a base the projection never consults.
EXCEPTION_ROOT = "System.Exception"

until queue.empty?
  identity = queue.shift
  next if selected.key?(identity)

  frame = bodies[identity]
  if frame.nil?
    abort "#{identity} not found in mscorlib IL" if FAMILIES.key?(identity)
    next
  end

  declaration = declaration_of(frame)
  record = declaration.merge("members" => [])
  annotate_properties(members(frame[:body])).each do |member|
    next unless surface?(member)

    facts = behaviour(member, throw_helper, support_literals)
    entry = {"kind" => member[:kind], "name" => member[:name], "access" => member[:access],
             "static" => member[:static], "explicitInterface" => member[:access] == "private"}
    entry["returnType"] = member[:returnType] if member.key?(:returnType)
    entry["parameters"] = member[:parameters] if member.key?(:parameters)
    entry["declaration"] = member[:declaration] if member.key?(:declaration)
    entry["accessors"] = member[:accessors] if member.key?(:accessors)
    entry["behaviour"] = facts if facts
    record["members"] << entry
    next if facts.nil?

    facts.fetch("throws", []).each do |thrown|
      exception = thrown.fetch("exception")
      queue << exception unless exception.start_with?("unresolved:")
    end
  end
  # An exception's own base chain is part of its identity, so walk it up to the projection root.
  base = declaration["baseType"]
  queue << base if base && bodies.key?(base) && identity != EXCEPTION_ROOT &&
                   (identity.end_with?("Exception") || identity == "System.SystemException")
  selected[identity] = record
end

families = FAMILIES.map do |family, reason|
  {"family" => family, "reason" => reason, "xnaConsumers" => consumers.fetch(family),
   "xnaConsumerCount" => consumers.fetch(family).length,
   "types" => selected.keys.select { |identity| identity == family || identity.start_with?("#{family}+") }.sort}
end

inventory = {
  "schemaVersion" => 1,
  "authority" => "Microsoft .NET Framework 4.0 mscorlib, the BCL the pinned XNA 4.0 Windows assemblies bind to",
  "separateFromXna" => "mscorlib is not an XNA assembly. Nothing here enters REFERENCE_TYPES, REFERENCE_MEMBERS or docs/generated/xna-il-inventory.json, and no BCL identity is an XNA identity.",
  "provenance" => "derived with ikdasm from a Microsoft .NET Framework 4.0 mscorlib admitted by exact SHA-256. No Microsoft-owned bytes, IL text or machine-local path is reproduced here.",
  "scope" => "demand-driven: a family is admitted only when the XNA reference contract names it, and only the surface those consumers can reach is recorded, plus the exception closure that surface throws",
  "assembly" => MSCORLIB.merge(
    "derivedPublicKeyToken" => derived_token,
    "publicKeyTokenDerivation" => "SHA-1 of the assembly's own .publickey blob, low eight bytes, reversed",
    "observedAssemblyVersion" => version,
    "observedFileVersion" => file_version
  ),
  "pairing" => {
    "rule" => "every pinned XNA assembly's AssemblyRef to mscorlib must name the exact version and public key token the admitted binary derives",
    "assemblies" => pairing
  },
  "throwHelperResolution" => throw_helper.sort.to_h,
  "BCL_FAMILIES" => families.length,
  "BCL_TYPES" => selected.length,
  "BCL_MEMBERS" => selected.values.sum { |record| record.fetch("members").length },
  "BCL_EXCEPTION_TYPES" => selected.keys.count { |identity| identity.end_with?("Exception") },
  "families" => families,
  "types" => selected.sort.to_h
}

File.write(File.join(root, "docs", "generated", "bcl-inventory.json"), JSON.pretty_generate(inventory) + "\n")

puts "BCL_ASSEMBLY=#{MSCORLIB.fetch("assemblyName")} #{version} #{derived_token}"
puts "BCL_ASSEMBLY_SHA256=#{actual_sha}"
puts "BCL_FAMILIES=#{inventory.fetch("BCL_FAMILIES")}"
puts "BCL_TYPES=#{inventory.fetch("BCL_TYPES")}"
puts "BCL_MEMBERS=#{inventory.fetch("BCL_MEMBERS")}"
puts "BCL_EXCEPTION_TYPES=#{inventory.fetch("BCL_EXCEPTION_TYPES")}"
puts "XNA_PAIRING_ASSEMBLIES=#{pairing.length}"
