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

inventory = {}
bodies = {}
calls = Hash.new { |hash, key| hash[key] = [] }
pinvoke = {}

assemblies.each do |name, path, sha256, size|
  il = IO.popen(["ikdasm", path], &:read)
  abort "ikdasm produced no IL for #{name}" if il.nil? || il.empty?

  current = nil
  body = nil
  method = nil
  header = nil
  il.each_line do |line|
    stripped = line.rstrip
    if line.start_with?(".class") && (match = /^\.class .*?([A-Za-z_][A-Za-z0-9_.`+'<>]*)\s*$/.match(stripped))
      current = match[1].tr("'", "")
      body = +""
      next
    end
    next unless current

    if stripped == "} // end of class #{current}"
      bodies[current] = body
      inventory[current] = {
        "assembly" => name,
        "assemblySha256" => sha256,
        "assemblyBytes" => size,
        "ilLines" => body.count("\n"),
        "nativeInteropMarkers" => NATIVE_MARKERS.select { |marker| body.include?(marker) }
      }
      current = nil
      body = nil
      method = nil
      next
    end
    body << line

    if stripped.lstrip.start_with?(".method ")
      header = +stripped
      method = nil
      next
    end
    if header
      header << " " << stripped
      # `pinvokeimpl("LIB" winapi)` and `marshal(...)` both carry a parenthesis that precedes the
      # method name, so they are removed before the name is read.
      searchable = header.gsub(/pinvokeimpl\s*\([^)]*\)/, " ").gsub(/marshal\s*\([^)]*\)/, " ")
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

    calls[method] << "#{target[1].tr("'", "")}::#{target[2]}"
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
      searchable = current[:text].gsub(/pinvokeimpl\s*\([^)]*\)/, " ").gsub(/marshal\s*\([^)]*\)/, " ")
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
    next unless stripped.start_with?("  } // end of method")

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
end

bodies.each do |type_name, body|
  entry = inventory[type_name]
  next unless entry

  entry["declaredFields"] = body.each_line.count { |line| line.lstrip.start_with?(".field ") }
  entry["constructors"] = constructor_facts(body)
  entry["declaredMethods"] = body.each_line.count { |line| line.start_with?("  } // end of method ") } -
                             entry["constructors"].length -
                             body.each_line.count { |line| line.start_with?("  } // end of method ") && line.include?("::.cctor") }
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
puts "NATIVE_ENTRY_POINT_METHODS=#{pinvoke.length}"
