# frozen_string_literal: true

module PallasTrade
  module Disputes
    # PALLAS-CUSTOM: DSP-P7-10 B1
    # (PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-…)
    #
    # SubmissionTimeline —— 争议证据**提交历史 / 版本 / 回执**追踪（FR-004）。
    #
    # 数据源：`DisputeEvidenceSubmission`（append-only、不可变、无金额列）。
    #   - 本服务**只读**：不写回执、不改状态、不触网；
    #   - `version` = 同一 `kind` 内按时间递增的序号（v1、v2…）；
    #   - `diff` = 相对**上一版同类提交**的证据键变化（added / removed / kept），用于人工比对；
    #   - provider 回执以 `provider_status` + `provider_reference` 如实呈现（缺失即 null，不推断）。
    class SubmissionTimeline
      prepend PallasTrade::ServiceModule::Base

      # @param dispute [PallasTrade::Dispute]
      # @param kind [String, nil] 仅看某类回执（evidence_submitted / accepted）
      # @return [PallasTrade::ServiceModule::Result] success({ entries:, count:, latest:, versions: })
      def call(dispute:, kind: nil)
        return success(empty) if dispute.nil?

        records = PallasTrade::DisputeEvidenceSubmission
                  .for_dispute(dispute)
                  .then { |scope| kind.present? ? scope.by_kind(kind) : scope }
                  .to_a

        ordered = records.sort_by { |r| [r.created_at, r.id] }
        counters = Hash.new(0)
        previous_by_kind = {}
        entries = ordered.map do |record|
          counters[record.kind] += 1
          entry = build_entry(record, counters[record.kind], previous_by_kind[record.kind])
          previous_by_kind[record.kind] = record
          entry
        end

        success({
                  entries: entries.reverse, # 最新在前（控制台展示序）；version 仍按时间递增
                  count: entries.size,
                  latest: entries.last,
                  versions: entries.group_by { |e| e[:kind] }.transform_values { |items| items.size },
                  kinds: entries.map { |e| e[:kind] }.uniq
                })
      end

      private

      def empty
        { entries: [], count: 0, latest: nil, versions: {}, kinds: [] }
      end

      def build_entry(record, version, previous)
        keys = evidence_keys(record)
        {
          id: record.respond_to?(:prefixed_id) ? record.prefixed_id : record.id,
          kind: record.kind,
          version: version,
          at: record.created_at,
          actor: actor_for(record),
          late: record.late == true,
          provider_status: record.provider_status,
          provider_reference: record.provider_reference,
          payload_digest: record.payload_digest.to_s[0, 12],
          evidence_keys: keys,
          files_count: file_count(record),
          diff: diff_for(previous, keys),
          previous_id: previous && (previous.respond_to?(:prefixed_id) ? previous.prefixed_id : previous.id)
        }
      end

      def diff_for(previous, keys)
        return { added: keys, removed: [], kept: [], first: true } if previous.nil?

        previous_keys = evidence_keys(previous)
        {
          added: keys - previous_keys,
          removed: previous_keys - keys,
          kept: keys & previous_keys,
          first: false
        }
      end

      def evidence_keys(record)
        metadata = record.respond_to?(:response_metadata) ? record.response_metadata : nil
        keys = metadata.is_a?(Hash) ? metadata['evidence_keys'] : nil
        Array(keys).map(&:to_s).sort
      end

      def file_count(record)
        return 0 unless record.respond_to?(:evidence_files)

        record.evidence_files.attached? ? record.evidence_files.count : 0
      end

      def actor_for(record)
        {
          type: record.actor_type,
          id: record.actor_id,
          label: record.actor_label
        }
      end
    end
  end
end
