# ISeq caching: useful, private, and not the boot format

CRuby 4.0.6 can serialize a `RubyVM::InstructionSequence` with `to_binary` and
load it with `load_from_binary`. Ruby's own API documentation is explicit that
the result cannot move between Ruby versions, architectures, or machines. It
also warns that the loader has no verifier and malformed input can be fatal.

RubyOS therefore treats ISeq as an optional, trusted cache—not a distributable
kernel format. `make test-iseq` exercises `tools/freeze-iseq.rb` with the
source-built Ruby and records engine, version, revision, platform, source hash,
and binary hash beside the cache. Source remains authoritative.

The present host cross-build cannot safely freeze the bare-metal kernel: the
build interpreter reports `aarch64-linux`, while the ARM64 kernel reports
`aarch64-none`. Matching the marketing version is insufficient. A future boot
cache must be produced by the exact target Ruby build (or by an upstream
verified, target-aware compiler) and must fail back to source on any manifest
mismatch. Until then, embedding readable Ruby source is the correct design.
