#!/usr/bin/env ruby
# lib-normalize.rb — deploy-boundary frontmatter normalization for VENDOR skills.
# Usage: ruby lib-normalize.rb <node-skill-dir>...
#
# Governance (design G1/G7 refinement, 2026-11-07): the vendor mirror stays
# byte-faithful to upstream — upstream skills do not owe us our conventions.
# Non-compliance with strict parsers (dsh drops skills whose frontmatter plain
# scalars contain ": ") is repaired HERE, at materialization: only the node
# copy is normalized, the repo mirror is never touched. doctor C1b watches the
# repo side and reports upstream non-compliance as a vendor-zone warning.
#
# Narrow scope: only repairs the observed failure class — a single-line
# `description:` plain scalar containing ": ". Everything else is left as-is
# (reported to stderr as "normalize failed" so doctor can see it).
require 'yaml'

ARGV.each do |dir|
  p = File.join(dir, 'SKILL.md')
  raw = File.read(p) rescue next
  m = raw.match(/\A---\r?\n(.*?)\r?\n---\r?\n/m) or next
  begin
    YAML.safe_load(m[1])
    next                                     # already valid — idempotent no-op
  rescue StandardError
  end
  fixed = m[1].gsub(/^(description:[ \t]*)([^\n]+)$/) do
    v = Regexp.last_match(2)
    if v.start_with?("'", '"') || v.include?('\\')
      v                                      # already quoted or exotic — don't touch
    else
      "#{Regexp.last_match(1)}'" + v.gsub("'", "''") + "'"
    end
  end
  begin
    YAML.safe_load(fixed)
    File.write(p, raw.sub(m[1]) { fixed })
    warn "normalized frontmatter: #{p}"
  rescue StandardError
    warn "normalize failed (left as-is, doctor watches): #{p}"
  end
end
