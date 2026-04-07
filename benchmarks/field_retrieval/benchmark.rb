# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "securerandom"
require "uri"

# Standalone experiment: no ElasticGraph installation or Bundler required.
# See README.md for methodology, existing-index mode, and interpretation.
module FieldRetrievalBenchmark
  class Client
    def initialize(url)
      uri = URI(url)
      raise ArgumentError, "URL must be an HTTP(S) origin without credentials, query, or path" unless
        %w[http https].include?(uri.scheme) && uri.host && ["", "/"].include?(uri.path) && !uri.userinfo && !uri.query

      @http = Net::HTTP.new(uri.host, uri.port)
      @http.use_ssl = uri.scheme == "https"
      @http.open_timeout = 10
      @http.read_timeout = 120
      @http.max_retries = 0
      @http.start
    end

    def close
      @http.finish
    end

    def request(method, path, body = nil)
      request = Net::HTTPGenericRequest.new(method, !body.nil?, true, path)
      request["Content-Type"] = "application/json"
      request["Accept-Encoding"] = "identity"
      request["Authorization"] = ENV.fetch("BENCH_AUTHORIZATION") if ENV.key?("BENCH_AUTHORIZATION")
      request.body = body.is_a?(String) ? body : JSON.generate(body) unless body.nil?
      response = @http.request(request)
      raise "HTTP #{response.code} for #{method} #{path}" unless response.is_a?(Net::HTTPSuccess)
      [JSON.parse(response.body), response.body.bytesize]
    end
  end

  # Deliberately narrower than datastore support. Unknown mappings are not evidence
  # that source and doc values are interchangeable. Arrays are checked per result.
  def self.eligible_mapping?(mapping)
    %w[keyword long integer short byte boolean].include?(mapping["type"]) &&
      (mapping.keys - %w[type doc_values store index]).empty? && mapping["doc_values"] != false
  end

  def self.payload(response, fields, source_fields)
    raise "Search timed out or returned failed shards" if response["timed_out"] || response.fetch("_shards").fetch("failed") > 0

    response.fetch("hits").fetch("hits").map do |hit|
      values = fields.to_h do |field|
        value = if source_fields.include?(field)
          hit.fetch("_source", {})[field]
        else
          entries = hit.fetch("fields", {}).fetch(field, [])
          raise "#{field} returned multiple values; only direct scalars are supported" if entries.size > 1
          entries.first
        end
        raise "#{field} is an object or list; only direct scalars are supported" if value.is_a?(Array) || value.is_a?(Hash)
        [field, value]
      end
      [hit.fetch("_index"), hit.fetch("_id"), values]
    end
  end

  def self.summary(samples)
    sorted = samples.sort
    {"median" => (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0,
     "p95" => sorted[(sorted.size * 0.95).ceil - 1]}
  end

  class Runner
    def initialize(client, options)
      @client = client
      @options = options
      @random = Random.new(options.fetch(:seed))
    end

    def run
      info, = @client.request("GET", "/")
      results = if @options[:index]
        index = @options.fetch(:index)
        fields = @options.fetch(:fields)
        mappings, = @client.request("GET", "/#{index}/_mapping")
        raise "Use one concrete index, not an alias" unless mappings.keys == [index]
        properties = mappings.fetch(index).fetch("mappings").fetch("properties", {})
        fields.each do |field|
          raise "#{field}: unsupported mapping" unless FieldRetrievalBenchmark.eligible_mapping?(properties.fetch(field, {}))
        end
        stored = fields.all? { |field| properties.fetch(field)["store"] == true }
        [measure(index, fields, @options.fetch(:query), stored: stored)]
      else
        @options.fetch(:padding).flat_map { |padding| synthetic(padding) }
      end
      {"datastore_version" => info.fetch("version"), "ruby" => RUBY_DESCRIPTION,
       "options" => @options.except(:url, :query, :index),
       "mode" => @options[:index] ? "existing index (read only)" : "synthetic",
       "results" => results}
    end

    def synthetic(padding)
      index = "eg-retrieval-bench-#{SecureRandom.hex(8)}"
      created = false
      fields = Array.new(@options.fetch(:counts).max) { |i| "f#{i}" }
      properties = fields.each_with_index.to_h { |field, i| [field, {type: i.even? ? "keyword" : "long", store: true}] }
      properties.merge!("ordinal" => {type: "long"}, "body" => {type: "text", index: false}, "label" => {type: "text"})
      @client.request("PUT", "/#{index}", {settings: {number_of_shards: 1, number_of_replicas: 0, refresh_interval: "-1"}, mappings: {properties: properties}})
      created = true
      @options.fetch(:documents).times.each_slice(100) do |ids|
        bulk = ids.flat_map do |id|
          document = fields.each_with_index.to_h { |field, i| [field, i.even? ? "value-#{id}-#{i}" : id * 100 + i] }
          # Seeded random bytes represented as hex avoid unrealistically compressible padding.
          document.merge!("ordinal" => id, "body" => @random.bytes((padding + 1) / 2).unpack1("H*")[0, padding], "label" => "document #{id}")
          [JSON.generate(index: {_id: id.to_s}), JSON.generate(document)]
        end.join("\n") + "\n"
        response, = @client.request("POST", "/#{index}/_bulk", bulk)
        raise "Bulk indexing failed" if response.fetch("errors")
      end
      @client.request("POST", "/#{index}/_refresh")
      @options.fetch(:counts).product(@options.fetch(:pages)).flat_map do |count, size|
        selected = fields.first(count)
        query = {"query" => {"match_all" => {}}, "sort" => [{"ordinal" => "asc"}], "size" => size, "track_total_hits" => false}
        [false, true].map do |mixed|
          measure(index, selected, query, stored: true, mixed: mixed).merge("padding_bytes" => padding)
        end
      end
    ensure
      # Only delete the random index successfully created by this invocation.
      @client.request("DELETE", "/#{index}") if created
    end

    def measure(index, fields, query, stored:, mixed: false)
      selected = mixed ? fields + ["label"] : fields
      variants = {"source" => [{"_source" => {"includes" => selected}}, selected]}
      source = mixed ? {"includes" => ["label"]} : false
      variants["docvalue_fields"] = [{"_source" => source, "docvalue_fields" => fields}, mixed ? ["label"] : []]
      unless mixed
        variants["fields"] = [{"_source" => false, "fields" => fields}, []]
        variants["stored_fields"] = [{"_source" => false, "stored_fields" => fields}, []] if stored
      end
      samples = variants.to_h { |name, _| [name, []] }
      baseline = nil
      (@options.fetch(:warmup) + @options.fetch(:iterations)).times do |iteration|
        variants.keys.shuffle(random: @random).each do |name|
          selection, source_fields = variants.fetch(name)
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          response, bytes = @client.request("POST", "/#{index}/_search?request_cache=false&preference=eg-retrieval-bench", query.merge(selection))
          value = FieldRetrievalBenchmark.payload(response, selected, source_fields)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000
          raise "Query returned no hits" if value.empty?
          baseline ||= value
          raise "Results differ for #{name}; stop writes and verify scalar semantics and deterministic sort" unless value == baseline
          samples.fetch(name) << {"wall_ms" => elapsed, "took_ms" => response.fetch("took"), "bytes" => bytes} if iteration >= @options.fetch(:warmup)
        end
      end
      result = {"field_count" => fields.size, "page_size" => query.fetch("size"), "mixed" => mixed,
                "returned_hits" => baseline.size, "variants" => samples.transform_values { |rows|
                  {"summary" => %w[wall_ms took_ms bytes].to_h { |key| [key, FieldRetrievalBenchmark.summary(rows.map { |row| row.fetch(key) })] }, "samples" => rows}
                }}
      warn "#{fields.size} scalars, page #{query.fetch("size")}, mixed=#{mixed}: " + result.fetch("variants").map { |name, data| "#{name}=#{data.dig("summary", "wall_ms", "median").round(3)}ms" }.join(", ")
      result
    end
  end

  def self.run(arguments)
    options = {url: "http://localhost:9234", documents: 2000, padding: [1024, 65536], counts: [1, 8, 32], pages: [10, 100], warmup: 20, iterations: 100, seed: 1110}
    query_path = nil
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby benchmark.rb [options] > results.json\nDefault: create, populate, benchmark, and delete isolated synthetic indices."
      opts.on("--url URL", "Datastore origin; BENCH_AUTHORIZATION supplies optional auth") { |value| options[:url] = value }
      opts.on("--index NAME", "Read-only existing-index mode (one concrete index)") { |value| options[:index] = value }
      opts.on("--fields LIST", Array, "Direct scalar field names for existing-index mode") { |value| options[:fields] = value }
      opts.on("--query FILE", "Search JSON with query/sort/size/from/track_total_hits only") { |value| query_path = value }
      %i[documents warmup iterations seed].each do |key|
        opts.on("--#{key} N", Integer) { |value| options[key] = value }
      end
      %i[padding counts pages].each do |key|
        opts.on("--#{key} LIST", Array) { |value| options[key] = value.map { |item| Integer(item) } }
      end
    end
    parser.parse!(arguments)
    raise ArgumentError, "Unexpected positional arguments" unless arguments.empty?
    raise ArgumentError, "documents and iterations must be positive; warmup nonnegative" unless options[:documents] > 0 && options[:iterations] > 0 && options[:warmup] >= 0
    %i[padding counts pages].each do |key|
      raise ArgumentError, "#{key} must contain positive integers" unless options[key].any? && options[key].all?(&:positive?)
    end
    if options[:index]
      raise ArgumentError, "Use one concrete index name" unless /\A[a-z0-9][a-z0-9_-]*\z/.match?(options[:index])
      raise ArgumentError, "--fields requires direct scalar names" unless options[:fields]&.any? && options[:fields].all? { |field| /\A[a-zA-Z][a-zA-Z0-9_]*\z/.match?(field) }
      query = query_path ? JSON.parse(File.read(query_path)) : {}
      raise ArgumentError, "Query accepts only query/sort/size/from/track_total_hits" unless query.is_a?(Hash) && (query.keys - %w[query sort size from track_total_hits]).empty?
      options[:query] = {"query" => {"match_all" => {}}, "sort" => ["_doc"], "size" => 100, "track_total_hits" => false}.merge(query)
      raise ArgumentError, "Query size must be a positive integer" unless options[:query]["size"].is_a?(Integer) && options[:query]["size"] > 0
    elsif options[:fields] || query_path
      raise ArgumentError, "--fields and --query require --index"
    end
    client = Client.new(options.fetch(:url))
    puts JSON.pretty_generate(Runner.new(client, options).run)
  ensure
    client&.close
  end
end

FieldRetrievalBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
