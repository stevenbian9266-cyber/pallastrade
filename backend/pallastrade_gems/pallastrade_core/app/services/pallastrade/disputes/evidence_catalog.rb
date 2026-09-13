# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-8 (PRD-20260913-payments-dsp-p7-8)
    #
    # EvidenceCatalog —— **provider 专属证据类型目录**（源计划 §68 的 `provider-specific evidence types`）。
    #
    # 职责边界：
    #   - 目录**来自 provider 适配器**（`PaymentMethod#dispute_evidence_catalog`；基类返回空 → 即"不支持"），
    #     核心不内置任何 provider 字段名 —— 新 provider 接入只需实现契约 + 目录；
    #   - 本服务做**校验与归一**：未知键拒绝、类型匹配（text/file）、文本长度上限、空载荷拒绝、
    #     文件白名单（大小/内容类型）；
    #   - **零 I/O、零写**：纯函数（校验不改任何状态，也不触网）。
    class EvidenceCatalog
      # 文本证据长度上限（与 Stripe evidence 字段上限对齐：20k 字符）
      MAX_TEXT_LENGTH = 20_000
      # 文件证据上限（Stripe dispute evidence 单文件 4.5MB / 常见 5MB 限制 → 取保守值）
      MAX_FILE_BYTES = 4_500_000
      ALLOWED_FILE_CONTENT_TYPES = %w[image/png image/jpeg image/gif application/pdf].freeze

      Entry = Struct.new(:key, :type, :max_length, :required, keyword_init: true) do
        def text?
          type.to_s == 'text'
        end

        def file?
          type.to_s == 'file'
        end
      end

      # @param payment_method [PallasTrade::PaymentMethod]
      def initialize(payment_method:)
        @payment_method = payment_method
      end

      # provider（或其网关子类）是否声明了证据目录 → 支持危险操作的前置条件之一
      def supported?
        entries.any?
      end

      def text_entries
        entries.select(&:text?)
      end

      def file_entries
        entries.select(&:file?)
      end

      def entries
        @entries ||= normalize_entries(raw_catalog)
      end

      def entry(key)
        entries.find { |e| e.key == key.to_s }
      end

      # 校验并归一提交载荷。
      # @param evidence [Hash] { "<key>" => String(文本) | 文件对象/散列 }
      # @return [Hash] { ok: Boolean, errors: [String], text: {key=>String}, files: {key=>Object} }
      def validate(evidence)
        provided = (evidence || {}).transform_keys(&:to_s).reject { |_k, v| v.respond_to?(:empty?) ? v.empty? : v.nil? }
        errors = []
        text = {}
        files = {}

        if provided.empty?
          errors << 'evidence_empty'
          return result(false, errors, text, files)
        end

        provided.each do |key, value|
          matched = entry(key)
          if matched.nil?
            errors << "unknown_evidence_key:#{key}"
            next
          end

          if matched.file?
            file_errors = validate_file(value, matched)
            file_errors.any? ? errors.concat(file_errors) : files[matched.key] = value
          else
            text_errors = validate_text(value, matched)
            text_errors.any? ? errors.concat(text_errors) : text[matched.key] = value.to_s
          end
        end

        result(errors.empty?, errors, text, files)
      end

      private

      def result(ok, errors, text, files)
        { ok: ok, errors: errors, text: text, files: files }
      end

      def raw_catalog
        return [] unless @payment_method.respond_to?(:dispute_evidence_catalog)

        @payment_method.dispute_evidence_catalog || []
      rescue ::NotImplementedError
        []
      end

      def normalize_entries(raw)
        Array(raw).map do |item|
          item = item.symbolize_keys if item.respond_to?(:symbolize_keys)
          Entry.new(
            key: item[:key].to_s,
            type: (item[:type] || 'text').to_s,
            max_length: item[:max_length] || MAX_TEXT_LENGTH,
            required: item[:required] ? true : false
          )
        end.reject { |e| e.key.empty? }
      end

      def validate_text(value, entry)
        errors = []
        errors << "evidence_not_text:#{entry.key}" unless value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(Symbol)
        errors << "evidence_too_long:#{entry.key}" if value.to_s.length > entry.max_length
        errors
      end

      def validate_file(value, entry)
        errors = []
        unless file_like?(value)
          errors << "evidence_not_file:#{entry.key}"
          return errors
        end

        size = file_size(value)
        content_type = file_content_type(value)
        errors << "evidence_file_too_large:#{entry.key}" if size && size > MAX_FILE_BYTES
        if content_type.present? && !ALLOWED_FILE_CONTENT_TYPES.include?(content_type)
          errors << "evidence_file_type_not_allowed:#{entry.key}:#{content_type}"
        end
        errors
      end

      # 文件判定：常见上传对象（UploadedFile/ActiveStorage::Blob/Tempfile/带 path 的 IO）
      def file_like?(value)
        return true if defined?(ActionDispatch::Http::UploadedFile) && value.is_a?(ActionDispatch::Http::UploadedFile)
        return true if defined?(ActiveStorage::Blob) && value.is_a?(ActiveStorage::Blob)
        return false unless value.respond_to?(:read)

        value.respond_to?(:original_filename) || value.respond_to?(:filename) ||
          value.respond_to?(:path) || value.respond_to?(:tempfile)
      end

      def file_size(value)
        return value.size if value.respond_to?(:size) && value.size.is_a?(Integer)
        return value.byte_size if value.respond_to?(:byte_size)

        nil
      end

      def file_content_type(value)
        return value.content_type.to_s if value.respond_to?(:content_type)

        nil
      end
    end
  end
end
