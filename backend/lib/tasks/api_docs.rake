# frozen_string_literal: true

# R1 (2026-09-04): Deterministic regeneration + validation of the OpenAPI docs
# at backend/public/api-docs/{store,admin}.yaml.
#
# Design (方案 A — Schema auto-generation, Paths stay curated):
#   * Only the Typelizer-owned `components.schemas` entries are regenerated
#     (entries marked `x-typelizer: true`, or produced by the serializers via
#     PallasTrade::Api::OpenAPI::SchemaHelper). Hand-authored (non-Typelizer)
#     schema entries and every byte outside the schemas region (openapi/info/
#     tags/paths/components.<other>) are preserved unchanged.
#   * `api:docs:schemas:generate` rewrites the files; `api:docs:schemas:check`
#     fails (exit 1) when generation would change anything (drift gate, wired
#     into `harness generated:check`).
#   * `api:docs:validate` parses both files with Psych and asserts every
#     `#/components/schemas/X` $ref target exists (path maintenance guard).
#   * SDK TypeScript types are produced separately by `rake typelizer:generate`
#     (store/admin writers) — chain via `api:docs:generate` / `api:docs:check`.
#
# Environment: run inside the Rails app (host backend, docker web container at
# /rails). Files are written with LF endings and Psych default style so output
# is deterministic and idempotent (generate twice == generate once).

require 'yaml'
require 'pallastrade/api/openapi/schema_helper'
require 'pallastrade/api/openapi/path_sorter'

module PallasTrade
  module ApiDocs
    DOCS = {
      store: 'public/api-docs/store.yaml',
      admin: 'public/api-docs/admin.yaml'
    }.freeze

    SCHEMA_NAME = /\A {4}([A-Za-z0-9_]+):\s*$/
    # Admin-only common schemas (SchemaHelper#common_schemas are shared) that
    # must not appear in the Store doc: they reference admin serializers
    # (AdminUser) which the store writer rejects. Kept out of store generation
    # so store.yaml stays resolvable.
    STORE_FORCE_DROP = %w[AdminUser MeResponse PermissionRule].freeze

    module_function

    def path_for(key)
      File.expand_path(DOCS.fetch(key), Rails.root)
    end

    # Full generated schema map for a writer: { 'Name' => deep-stringified hash }
    def generated_schemas(key)
      helper = PallasTrade::Api::OpenAPI::SchemaHelper
      raw = key == :admin ? helper.admin_schemas : helper.all_schemas
      raw.each_with_object({}) do |(name, schema), out|
        out[name.to_s] = normalize_scalars(deep_stringify(schema))
      end
    end

    # Typelizer returns Ruby Symbols for OpenAPI type tokens (:object/:string/
    # :integer/...) and emits $ref components for custom scalar types. Deep-
    # stringify BOTH keys and symbol values, then expand the known custom
    # scalar `iso8601` (ts_mapper-only type) into a proper OpenAPI string.
    def deep_stringify(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), out| out[k.to_s] = deep_stringify(v) }
      when Array
        value.map { |v| deep_stringify(v) }
      when Symbol
        value.to_s
      else
        value
      end
    end

    ISO8601_REF = { '$ref' => '#/components/schemas/iso8601' }.freeze

    def normalize_scalars(value)
      case value
      when Hash
        return { 'type' => 'string', 'format' => 'date-time' } if value == ISO8601_REF

        value.each_with_object({}) { |(k, v), out| out[k] = normalize_scalars(v) }
      when Array
        value.map { |v| normalize_scalars(v) }
      else
        value
      end
    end

    # Returns [prefix, entries, suffix] where entries is the raw text of the
    # existing `components.schemas` region (excluding the `  schemas:` line).
    # prefix ends with the `  schemas:` line + "\n".
    def split_document(text)
      lines = text.lines
      schemas_idx = nil
      components_idx = nil
      lines.each_with_index do |line, i|
        components_idx = i if line =~ /\Acomponents:\s*$/
        if components_idx && i > components_idx && line =~ /\A {2}schemas:\s*$/
          schemas_idx = i
          break
        end
      end
      return nil unless schemas_idx

      region_start = schemas_idx + 1
      # Find end of the schemas region: first non-blank line not indented >= 4.
      region_end = region_start
      while region_end < lines.size
        line = lines[region_end]
        break if line.strip != '' && line !~ /\A {4,}/

        region_end += 1
      end
      prefix = lines[0..schemas_idx].join
      suffix = lines[region_end..].to_a.join
      entries = parse_entries(lines[region_start...region_end])
      [prefix, entries, suffix]
    end

    # entries => { name => { owned: bool, text: string } } preserving file order.
    # text is the FULL verbatim block including the leading `    Name:` line so
    # preserved (non-owned) entries round-trip byte-for-byte.
    def parse_entries(region_lines)
      entries = {}
      current_name = nil
      current_header = nil
      buffer = []
      region_lines.each do |line|
        if (m = line.match(SCHEMA_NAME))
          flush_entry(entries, current_name, current_header, buffer) if current_name
          current_name = m[1]
          current_header = line
          buffer = []
        else
          buffer << line
        end
      end
      flush_entry(entries, current_name, current_header, buffer) if current_name
      entries
    end

    def flush_entry(entries, name, header, buffer)
      return if name.nil? || header.nil?

      text = "#{header}#{buffer.join}"
      entries[name] = { owned: text.include?('x-typelizer: true'), text: text }
    end

    # Emit one schema entry: `    Name:\n` + body indented to column 6.
    def dump_entry(name, schema_hash)
      body = Psych.dump(schema_hash)
      body = body.sub(/\A---\n/, '')
      indented = body.lines.map { |l| l == "\n" ? l : "      #{l}" }.join
      "    #{name}:\n#{indented}"
    end

    # Merge: keep file order; drop owned entries no longer generated; refresh
    # owned-kept from generated; preserve non-owned verbatim; append new
    # generated entries (new serializers) at the end.
    def merged_entries(existing, generated, force_drop: [])
      result = []
      seen = {}
      existing.each_key do |name|
        next if force_drop.include?(name)

        entry = existing[name]
        if entry[:owned]
          next unless generated.key?(name) # dropped: serializer removed

          result << [name, dump_entry(name, generated[name])]
        else
          # Hand-authored / common — preserved byte-for-byte (verbatim block).
          result << [name, entry[:text]]
        end
        seen[name] = true
      end
      generated.each_key do |name|
        next if seen[name]

        result << [name, dump_entry(name, generated[name])]
      end
      result.map(&:last).join
    end

    def regenerated_text(key, text)
      split = split_document(text)
      return text unless split

      prefix, entries, suffix = split
      generated = generated_schemas(key)
      force_drop = key == :store ? STORE_FORCE_DROP : []
      force_drop.each { |name| generated.delete(name) }
      body = merged_entries(entries, generated, force_drop: force_drop)
      "#{prefix}#{body}#{suffix}"
    end

    def with_lf(content)
      content.gsub("\r\n", "\n")
    end

    # Writes the regenerated doc when it differs; returns whether it changed.
    def file_changed?(key)
      file = path_for(key)
      original = with_lf(File.read(file))
      rewritten = regenerated_text(key, original)
      if rewritten == original
        false
      else
        File.write(file, rewritten)
        true
      end
    end

    def check_file(key)
      file = path_for(key)
      original = with_lf(File.read(file))
      rewritten = regenerated_text(key, original)
      changed = rewritten != original
      puts "#{DOCS.fetch(key)}: #{changed ? 'DRIFT' : 'clean'}"
      changed
    end

    # Parses + checks every $ref used from `paths`; returns whether the doc is valid.
    def doc_valid?(key)
      file = path_for(key)
      doc = Psych.safe_load(
        File.read(file),
        permitted_classes: [Symbol, Date, Time],
        aliases: true
      )
      schemas = doc.dig('components', 'schemas') || {}

      # Hard gate: every $ref used from `paths` must resolve (endpoint contract
      # integrity — the "Paths stay curated" guarantee). Refs inside component
      # schemas are only warned: hand-authored (non-serializer) schemas may
      # still carry legacy content and get replaced once a serializer exists.
      missing_path = []
      walk_refs(doc['paths']) do |ref|
        name = ref.to_s.sub(%r{\A#/components/schemas/}, '')
        next if name == ref.to_s # external/non-schema ref — ignore

        missing_path << name unless schemas.key?(name)
      end
      missing_path.uniq!
      if missing_path.any?
        puts "#{DOCS.fetch(key)}: paths reference missing schemas => #{missing_path.join(', ')}"
        return false
      end

      # Soft scan inside components (informational).
      missing_internal = []
      walk_refs(schemas) do |ref|
        name = ref.to_s.sub(%r{\A#/components/schemas/}, '')
        next if name == ref.to_s

        missing_internal << name unless schemas.key?(name)
      end
      missing_internal.uniq!
      puts "#{DOCS.fetch(key)}: WARN components-internal dangling refs (hand schema debt) => #{missing_internal.join(', ')}" if missing_internal.any?

      puts "#{DOCS.fetch(key)}: valid (#{schemas.size} schemas; all path $refs resolve)"
      true
    end

    # Walk the document for real $ref keys, skipping literal example payloads
    # (example/examples/default values are data, not references).
    LITERAL_KEYS = %w[example examples default].freeze

    def walk_refs(node, &block)
      case node
      when Hash
        node.each do |k, v|
          if k == '$ref' && v.is_a?(String)
            block.call(v)
          elsif LITERAL_KEYS.include?(k)
            next # example/default payloads are not references
          else
            walk_refs(v, &block)
          end
        end
      when Array
        node.each { |v| walk_refs(v, &block) }
      end
    end
  end
end

namespace :api do
  namespace :docs do
    desc 'Regenerate Typelizer-owned components.schemas in store/admin OpenAPI YAML'
    task schemas: :environment do
      changed = []
      PallasTrade::ApiDocs::DOCS.each_key do |key|
        changed << key if PallasTrade::ApiDocs.file_changed?(key)
      end
      if changed.any?
        puts "Regenerated: #{changed.join(', ')}"
      else
        puts 'No schema drift detected.'
      end
    end

    desc 'Check Typelizer-owned schemas are current (exit 1 on drift)'
    task 'schemas:check': :environment do
      drift = PallasTrade::ApiDocs::DOCS.keys.any? do |key|
        PallasTrade::ApiDocs.check_file(key)
      end
      exit 1 if drift
    end

    desc 'Validate store/admin OpenAPI YAML (Psych parse + $ref integrity)'
    task validate: :environment do
      ok = PallasTrade::ApiDocs::DOCS.keys.all? do |key|
        PallasTrade::ApiDocs.doc_valid?(key)
      end
      exit 1 unless ok
    end

    desc 'Generate SDK TS types + OpenAPI schemas (full contract regeneration)'
    task generate: :environment do
      Rake::Task['typelizer:generate'].invoke
      Rake::Task['api:docs:schemas'].invoke
    end

    desc 'Idempotency/drift check for SDK TS types + OpenAPI schemas'
    task check: :environment do
      Rake::Task['typelizer:generate'].invoke
      Rake::Task['api:docs:schemas:check'].invoke
    end
  end
end
