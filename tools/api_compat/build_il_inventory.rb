# frozen_string_literal: true

# Derives the Microsoft-free IL inventory from the pinned original XNA 4.0 Windows assemblies.
#
# Point XNA_REFERENCE_ASSEMBLIES at a directory holding them. Every assembly is located and
# admitted by exact SHA-256, never by filename, and the tool refuses to run if any hash differs.
# Nothing Microsoft-owned is written: the output records which assembly declares each reference
# type, and whether that type's own IL crosses the native interop boundary.

require "digest"
require "json"

PINNED = {
  "Microsoft.Xna.Framework.dll" => "38e7093f52d7474bbc6256906519781a1210d7da50a1c667b52716fcf49ca130",
  "Microsoft.Xna.Framework.Graphics.dll" => "560080fc39021c611ca9d076dcebed312faf6d7d1413c2dc523683ea635e9f55",
  "Microsoft.Xna.Framework.Game.dll" => "b5dffdd8125abef2a4507ba4e1d2f11062143f0a63d48fe4f298b95ad746a1f0",
  "Microsoft.Xna.Framework.Input.Touch.dll" => "b0585224c18022c3661057ae79544644c10f33f1dc529678364f3d6b25151c25",
  "Microsoft.Xna.Framework.Xact.dll" => "a14d5364dca7cf49fb90639e87ba04d52b59a700dc9198efa5707ce8eae28f0a",
  "Microsoft.Xna.Framework.Storage.dll" => "798f678e9ae3d9afc3bed66c30123bc9634fb923b6d200188344b618e608cbb8",
  "Microsoft.Xna.Framework.Video.dll" => "17538b1ca9d48a993e2cd88c96b436df08e7abb4aec5d4758eb21feb580d6e06",
  "Microsoft.Xna.Framework.Net.dll" => "39739dbf5f6ba02e1d0b02ed404f6fe0692497848bc1a6a25be132d47ed9c151",
  "Microsoft.Xna.Framework.GamerServices.dll" => "7c6effed97aa25a95c5e095d9c261f5581e402180cc073271a367b9eef79c8af",
  "Microsoft.Xna.Framework.Avatar.dll" => "b3c70bbe469000b9e11507cc63b88d54a4e0bc5c27afc826d66e0aee51640871"
}.freeze

root = File.expand_path("../..", __dir__)
directory = ENV.fetch("XNA_REFERENCE_ASSEMBLIES") do
  abort "XNA_REFERENCE_ASSEMBLIES must name a directory holding the pinned XNA 4.0 Windows assemblies"
end
unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |entry| File.executable?(File.join(entry, "ikdasm")) }
  abort "ikdasm is required and was not found on PATH (Debian package: ikdasm)"
end

# Admission is by hash. A file whose name matches but whose bytes do not is not authoritative.
assemblies = PINNED.map do |name, expected|
  path = File.join(directory, name)
  abort "missing pinned assembly #{name}" unless File.file?(path)
  actual = Digest::SHA256.file(path).hexdigest
  abort "SHA-256 mismatch for #{name}: expected #{expected}, got #{actual}" unless actual == expected

  [name, path, expected, File.size(path)]
end

# `ikdasm` writes one `.class` line per type and one `} // end of class <name>` line closing it.
# A method marked `pinvokeimpl` is a direct native entry point; the interop namespaces below are
# the managed side of the same boundary. Both are recorded, never guessed at.
NATIVE_MARKERS = [
  "pinvokeimpl",
  "System.Runtime.InteropServices.Marshal",
  "System.Runtime.InteropServices.SafeHandle",
  "System.Runtime.InteropServices.GCHandle",
  "System.Runtime.InteropServices.ComTypes"
].freeze

# Method-level call graph across the pinned assemblies. A node is "FullTypeName::MethodName";
# overloads share a node, which only ever over-approximates within a single type.
CALL = /^\s+IL_[0-9a-f]{4}:\s+(?:call|callvirt|newobj|ldftn|ldvirtftn|jmp)\s+(.*)$/.freeze
# XNA 4.0's Framework and Graphics assemblies are mixed-mode C++/CLI: most native work is an
# indirect `calli` through an unmanaged calling convention rather than a classic P/Invoke, and the
# managed thunks that wrap it carry a CallConv modopt. Both forms are direct native entry points.
CALLI = /^\s+IL_[0-9a-f]{4}:\s+calli\s+(.*)$/.freeze
UNMANAGED = /\bunmanaged\s+(?:cdecl|stdcall|fastcall|thiscall|winapi)\b/.freeze
TARGET = /(?:\[[^\]]+\])?([A-Za-z_][A-Za-z0-9_.`+'<>\/]*)::([A-Za-z_.<>][A-Za-z0-9_.<>`]*)/.freeze
METHOD_NAME = /([A-Za-z_.<>][A-Za-z0-9_.<>`]*)\s*\(/.freeze
# The generic parameter list `ikdasm` appends to a `.class` declaration but omits from its closing
# comment.
GENERIC_SUFFIX = /<[^<>]*>\z/.freeze

# Everything in a `.method` header that carries a parenthesis *before* the method name, so a
# leading-identifier search cannot mistake it for the name.
#
# `pinvokeimpl("LIB" winapi)` and `marshal(...)` were always here. `modopt(...)` and `modreq(...)`
# were not, and their absence silently cost native reachability across the whole mixed-mode C++/CLI
# surface: XNA's native-methods classes declare their thunks as
# `.method public hidebysig static int32 modopt([mscorlib]...IsLong) Play(uint32)`, so every one of
# them was recorded under the name `modopt` while every call site resolved to `::Play`, and every
# edge into them dangled. Both sides now agree.
HEADER_NOISE = /(?:pinvokeimpl|marshal|modopt|modreq)\s*\([^)]*\)/.freeze

def sanitise_header(text) = text.gsub(HEADER_NOISE, " ")

inventory = {}
bodies = {}
calls = Hash.new { |hash, key| hash[key] = [] }
pinvoke = {}

assemblies.each do |name, path, sha256, size|
  il = IO.popen(["ikdasm", path], &:read)
  abort "ikdasm produced no IL for #{name}" if il.nil? || il.empty?

  # One frame per open `.class`, innermost last. `ikdasm` indents a nested type inside its
  # declaring type and closes it with the **short** name, which is why the first version of this
  # scanner -- anchored on a `.class` in column zero -- never saw one. It folded every nested
  # type's lines, fields and methods into its parent instead, so five reference types were
  # reported as carrying no IL while five others counted their children as their own.
  open = []
  method = nil
  header = nil
  il.each_line do |line|
    stripped = line.rstrip
    indent = line[/\A */].length
    leading = stripped.lstrip
    if leading.start_with?(".class ") && !leading.start_with?(".class extern")
      # `ikdasm` always writes the declared name last on the `.class` line, and quotes a name that
      # is not a plain identifier -- the compiler-generated `'<>c__DisplayClass3'` closures, for
      # one. The closing comment quotes it the same way, so both sides are unquoted before they are
      # compared; reading the name with a leading-identifier regex instead silently truncated every
      # quoted name and left its frame open forever.
      # A generic type is declared `Name`1<T>` and closed as `Name`1`, so the trailing generic
      # parameter list is dropped from both the recorded name -- which then matches the CLR
      # spelling the reference contract uses -- and the comparison below.
      short = stripped.split(/\s+/).last.to_s.tr("'", "").sub(GENERIC_SUFFIX, "")
      # A `.class` at this indent ends any frame at the same or deeper indent that never saw its
      # closing comment, so one malformed type cannot swallow the rest of the assembly. The
      # column-zero scanner already discarded such frames, by overwriting its single `current`.
      open.pop while !open.empty? && open.last[:indent] >= indent
      # A nested type is addressed the way the reference contract spells it, Parent+Child, rather
      # than the way an IL reference spells it, Parent/Child. Both are normalised to `+`.
      open << { name: open.empty? ? short : "#{open.last[:name]}+#{short}", short: short,
                body: +"", indent: indent }
      method = nil
      header = nil
      next
    end
    next if open.empty?

    current = open.last[:name]
    if leading.start_with?("} // end of class ") && indent == open.last[:indent] &&
       leading.sub("} // end of class ", "").tr("'", "").sub(GENERIC_SUFFIX, "") == open.last[:short]
      frame = open.pop
      bodies[frame[:name]] = frame[:body]
      inventory[frame[:name]] = {
        "assembly" => name,
        "assemblySha256" => sha256,
        "assemblyBytes" => size,
        "ilLines" => frame[:body].count("\n"),
        "nativeInteropMarkers" => NATIVE_MARKERS.select { |marker| frame[:body].include?(marker) }
      }
      method = nil
      header = nil
      next
    end
    # Only the innermost open type owns the line: a parent no longer absorbs its children.
    open.last[:body] << line

    if stripped.lstrip.start_with?(".method ")
      header = +stripped
      method = nil
      next
    end
    if header
      header << " " << stripped
      searchable = sanitise_header(header)
      if (match = METHOD_NAME.match(searchable))
        method = "#{current}::#{match[1]}"
        pinvoke[method] = true if header.include?("pinvokeimpl")
        calls[method] ||= []
        header = nil
      end
      next
    end
    next unless method

    if (indirect = CALLI.match(stripped)) && UNMANAGED.match?(indirect[1])
      pinvoke[method] = true
      next
    end
    next unless (match = CALL.match(stripped))

    target = TARGET.match(match[1])
    next unless target

    # IL spells a nested type Parent/Child; the reference contract, the inventory keys and the
    # method nodes above all spell it Parent+Child. Normalising here is what lets an edge into a
    # nested type land on a node that exists, instead of dangling.
    calls[method] << "#{target[1].tr("'", "").tr("/", "+")}::#{target[2]}"
  end
end

# Fixpoint: a method is native-reachable when it is a P/Invoke or calls one, transitively. Only
# edges landing inside the pinned assembly set are followed; everything else is BCL and managed.
known = calls.keys.to_h { |node| [node, true] }
reachable = pinvoke.dup
loop do
  added = false
  calls.each do |node, targets|
    next if reachable[node]
    next unless targets.any? { |target| reachable[target] }

    reachable[node] = true
    added = true
  end
  break unless added
end

# Per-type structural facts derived straight from the IL: how many fields the type declares, which
# non-constructor methods it declares, and for each constructor whether its whole body is a pure
# forward to the base constructor (`ldarg.0 [ldarg.1 [ldarg.2 ...]] call base::.ctor ret`).
def constructor_facts(body)
  facts = []
  current = nil
  body.each_line do |line|
    stripped = line.rstrip
    if stripped.lstrip.start_with?(".method ") || (current && current[:header])
      current = {header: true, access: nil, parameters: 0, ops: [], text: +""} unless current&.dig(:header)
      current[:text] << " " << stripped
      searchable = sanitise_header(current[:text])
      if (match = /([A-Za-z_.<>][A-Za-z0-9_.<>`]*)\s*\(/.match(searchable))
        current[:header] = false
        current[:name] = match[1]
        current[:access] = %w[public private family assembly famorassem].find { |token| current[:text].include?(" #{token} ") } || "public"
      end
      next
    end
    next unless current

    if (operation = /^\s+IL_[0-9a-f]{4}:\s+(\S+)(?:\s+(.*))?$/.match(stripped))
      current[:ops] << [operation[1], operation[2].to_s]
      next
    end
    # A nested type's methods are indented one level deeper than its parent's, so this is matched
    # after stripping the indent rather than at a fixed two spaces -- which is why no method inside
    # a nested type was ever finalised.
    next unless stripped.lstrip.start_with?("} // end of method")

    if current[:name] == ".ctor"
      operands = current[:ops]
      loads = operands.take_while { |op, _| op.start_with?("ldarg.") }
      tail = operands.drop(loads.length)
      pure = tail.length == 2 && tail[0][0] == "call" && tail[0][1].include?("::.ctor(") && tail[1][0] == "ret" &&
             loads.first&.first == "ldarg.0" && loads.each_with_index.all? { |(op, _), index| op == "ldarg.#{index}" }
      # leadingArgumentLoads counts the consecutive ldarg.N prefix; for a pure base forward that is
      # exactly the constructor's declared parameter count, and for anything else it is only the
      # prefix, so it is reported as such rather than as an argument count.
      facts << {"access" => current[:access], "leadingArgumentLoads" => [loads.length - 1, 0].max,
                "pureBaseForward" => pure, "instructions" => operands.length}
    end
    current = nil
  end
  facts
end

inventory.each do |type_name, entry|
  own = calls.keys.select { |node| node.start_with?("#{type_name}::") }
  native = own.select { |node| reachable[node] }
  entry["methodNodes"] = own.length
  entry["nativeReachableMethods"] = native.map { |node| node.split("::", 2).last }.uniq.sort
  entry["nativeReachable"] = !native.empty?
  entry["declaresNativeEntryPoint"] = own.any? { |node| pinvoke[node] }

  # The member-level half of the dependency graph.
  #
  # The signature graph in analyze_dependencies.rb can only see the types a public signature names,
  # so it answers "GameComponent depends on Game" and stops there. What the IL knows, and what
  # nothing recorded until now, is *which member* of that type the dependent actually calls:
  # GameComponent's whole body reaches exactly one, `Game::get_Components`. That is the difference
  # between a type being blocked on a partial dependency and being blocked on nothing at all.
  #
  # The edges are the ones the reachability fixpoint above already collects, so this adds no new
  # parsing and inherits the same normalisation -- a nested type spelled `Parent+Child`, a name
  # stripped of quotes. Only edges landing on a *different* XNA reference type are kept: a call
  # inside the type itself is not a dependency, and everything outside the pinned set is BCL, which
  # the signature graph already handles.
  entry["externalMemberReferences"] = own.flat_map { |node| calls.fetch(node, []) }
                                         .reject { |target| target.start_with?("#{type_name}::") }
                                         .uniq.sort
end

bodies.each do |type_name, body|
  entry = inventory[type_name]
  next unless entry

  entry["declaredFields"] = body.each_line.count { |line| line.lstrip.start_with?(".field ") }
  entry["constructors"] = constructor_facts(body)
  ends = body.each_line.select { |line| line.lstrip.start_with?("} // end of method ") }
  entry["declaredMethods"] = ends.length - entry["constructors"].length -
                             ends.count { |line| line.include?("::.cctor") }
end

reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
reference_names = reference.fetch("types").map { |type| type.fetch("name") }
covered = reference_names.select { |name| inventory.key?(name) }

report = {
  "schemaVersion" => 1,
  "profile" => reference.fetch("profile"),
  "provenance" => "derived with ikdasm from the pinned original XNA 4.0 Windows assemblies; located and admitted by exact SHA-256, never by filename. No Microsoft-owned bytes are reproduced here.",
  "assemblies" => assemblies.map do |name, _path, sha256, size|
    {"name" => name, "sha256" => sha256, "bytes" => size, "version" => "4.0.0.0"}
  end,
  "nativeReachabilityRule" => "a native entry point is a P/Invoke declaration or an indirect calli through an unmanaged calling convention, which is how XNA's mixed-mode C++/CLI assemblies reach native code. A type is native-reachable when any method it declares is a native entry point, or transitively calls one, following only call/callvirt/newobj/ldftn edges that land inside the pinned assembly set",
  "REFERENCE_TYPES" => reference_names.length,
  "TYPES_WITH_IL" => covered.length,
  "TYPES_WITHOUT_IL" => reference_names.length - covered.length,
  "TYPES_NATIVE_REACHABLE" => covered.count { |name| inventory.fetch(name).fetch("nativeReachable") },
  # The number the reachability fixpoint starts from: methods that are themselves a P/Invoke or an
  # unmanaged calli. It was printed but never written, so nothing could pin it; Native frontier 3
  # moved it from 214 to 254 and that had to be measurable rather than only observable in a log.
  "NATIVE_ENTRY_POINT_METHODS" => pinvoke.length,
  # Every member-level edge that lands on a reference type other than its own owner, keyed by the
  # type that makes the call. This is what lets a consumer ask whether a dependency on a *partial*
  # type is really unmet, member for member, instead of assuming it is.
  "MEMBER_LEVEL_EDGES" => covered.sum { |name| inventory.fetch(name).fetch("externalMemberReferences", []).length },
  "typesWithoutIl" => (reference_names - covered).sort,
  "types" => covered.sort.to_h { |name| [name, inventory.fetch(name)] }
}

destination = File.join(root, "docs", "generated", "xna-il-inventory.json")
File.write(destination, JSON.pretty_generate(report) + "\n")
puts "ASSEMBLIES=#{assemblies.length}"
puts "REFERENCE_TYPES=#{report["REFERENCE_TYPES"]}"
puts "TYPES_WITH_IL=#{report["TYPES_WITH_IL"]}"
puts "TYPES_WITHOUT_IL=#{report["TYPES_WITHOUT_IL"]}"
puts "TYPES_NATIVE_REACHABLE=#{report["TYPES_NATIVE_REACHABLE"]}"
puts "NATIVE_ENTRY_POINT_METHODS=#{report["NATIVE_ENTRY_POINT_METHODS"]}"
puts "MEMBER_LEVEL_EDGES=#{report["MEMBER_LEVEL_EDGES"]}"
