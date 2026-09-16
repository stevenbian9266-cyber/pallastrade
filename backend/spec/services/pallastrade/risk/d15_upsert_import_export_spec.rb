# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d15-risk-lists（D15 切片1，名单维护 / 导入导出）
#   AC-002 ← FR-002：CSV 批量导入（必填列、逐行错误不中断、幂等、续期、审计）
#   AC-003 ← FR-003：导出与导入同构（往返一致）+ 仅导出筛选结果
#   AC-004 ← FR-004：新增 / 续期 / 撤销 + 审计 before/after
RSpec.describe 'D15 risk list maintenance', type: :service do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }

  def entry_for(value, subject_type: 'email', list_type: 'denylist')
    PallasTrade::PaymentRiskList.find_by(list_type: list_type, subject_type: subject_type,
                                         value_hash: PallasTrade::PaymentRiskList.value_hash_for(
                                           list_type: list_type, subject_type: subject_type, value: value
                                         ))
  end

  describe 'Risk::Lists::Upsert (AC-004)' do
    it 'creates an entry, then renews the same entry on a second call' do
      first = PallasTrade::Risk::Lists::Upsert.call(
        list_type: 'denylist', subject_type: 'email', value: "d15-up-#{suffix}@Example.com",
        store: store, reason: 'first', actor: 'system'
      )
      expect(first).to be_success
      expect(first.value.masked_value).to eq("d***@example.com")

      second = PallasTrade::Risk::Lists::Upsert.call(
        list_type: 'denylist', subject_type: 'email', value: "D15-UP-#{suffix}@example.com",
        store: store, reason: 'renewed', expires_at: 3.days.from_now, actor: 'system'
      )
      expect(second).to be_success
      expect(second.value.id).to eq(first.value.id)
      expect(second.value.reason).to eq('renewed')
      expect(second.value.expires_at).to be_within(2.seconds).of(3.days.from_now)
    end

    it 'rejects unsupported types and blank values' do
      bad_type = PallasTrade::Risk::Lists::Upsert.call(list_type: 'greylist', subject_type: 'email', value: 'x@y.com')
      bad_subject = PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'shoe_size', value: '42')
      blank = PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email', value: '   ')

      expect(bad_type).not_to be_success
      expect(bad_subject).not_to be_success
      expect(blank).not_to be_success
    end

    it 'revokes without deleting and can be revived by another upsert' do
      created = PallasTrade::Risk::Lists::Upsert.call(
        list_type: 'denylist', subject_type: 'ip', value: '203.0.113.77', store: store, actor: 'system'
      ).value
      revoked = PallasTrade::Risk::Lists::Upsert.call(
        list_type: 'denylist', subject_type: 'ip', value: '203.0.113.77', store: store, actor: 'system', revoke: true
      )

      expect(revoked).to be_success
      expect(revoked.value.id).to eq(created.id)
      expect(revoked.value.status).to eq('revoked')
      expect(PallasTrade::PaymentRiskList.where(id: created.id).count).to eq(1)
      expect(PallasTrade::PaymentRiskList.active.where(id: created.id)).to be_empty

      revived = PallasTrade::Risk::Lists::Upsert.call(
        list_type: 'denylist', subject_type: 'ip', value: '203.0.113.77', store: store, actor: 'system'
      )
      expect(revived.value.status).to eq('active')
      expect(revived.value.id).to eq(created.id)
    end

    it 'writes an audit row with masked before/after snapshots' do
      PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email',
                                            value: "d15-audit-#{suffix}@example.com", store: store, actor: 'system')

      audit = PallasTrade::AuditLog.where(action: 'risk_list_entry_changed').order(:id).last
      expect(audit).to be_present
      expect(audit.after['masked_value']).to eq("d***@example.com")
      expect(audit.after.to_json).not_to include("d15-audit-#{suffix}@example.com")
    end
  end

  describe 'Risk::Lists::ImportCSV (AC-002)' do
    def csv(*rows)
      (['list_type,subject_type,value,expires_at,reason'] + rows).join("\n")
    end

    it 'imports rows, collects per-row errors and stays idempotent' do
      payload = csv(
        "denylist,email,d15-import-#{suffix}@Example.com,,bulk",
        "allowlist,email,d15-allow-#{suffix}@example.com,2026-12-31,trusted",
        "denylist,shoe_size,42,,bad subject",
        ",email,missing@example.com,,bad list",
        "denylist,email,,,missing value"
      )

      outcome = PallasTrade::Risk::Lists::ImportCSV.call(csv: payload, store: store, actor: 'system')
      expect(outcome).to be_success
      expect(outcome.value[:created]).to eq(2)
      expect(outcome.value[:updated]).to eq(0)
      expect(outcome.value[:errors].size).to eq(3)
      expect(outcome.value[:errors].map { |e| e[:row] }).to contain_exactly(4, 5, 6)
      expect(entry_for("d15-import-#{suffix}@example.com").value).to eq("d15-import-#{suffix}@example.com")

      again = PallasTrade::Risk::Lists::ImportCSV.call(csv: payload, store: store, actor: 'system')
      expect(again.value[:created]).to eq(0)
      expect(again.value[:updated]).to eq(2)
    end

    it 'renews an existing entry instead of duplicating it' do
      PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email',
                                            value: "d15-renew-#{suffix}@example.com", store: store, actor: 'system')

      outcome = PallasTrade::Risk::Lists::ImportCSV.call(
        csv: csv("denylist,email,d15-renew-#{suffix}@example.com,2027-01-01,renewed by csv"),
        store: store, actor: 'system'
      )

      expect(outcome.value[:created]).to eq(0)
      expect(outcome.value[:updated]).to eq(1)
      expect(PallasTrade::PaymentRiskList.where(value: "d15-renew-#{suffix}@example.com").count).to eq(1)
      expect(entry_for("d15-renew-#{suffix}@example.com").reason).to eq('renewed by csv')
    end

    it 'refuses empty input, missing columns and malformed CSV' do
      expect(PallasTrade::Risk::Lists::ImportCSV.call(csv: '')).not_to be_success
      expect(PallasTrade::Risk::Lists::ImportCSV.call(csv: "list_type,value\ndenylist,x@y.com")).not_to be_success
      expect(PallasTrade::Risk::Lists::ImportCSV.call(csv: "list_type,subject_type,value\n\"unclosed")).not_to be_success
    end

    it 'writes an audit row that never contains the raw value' do
      PallasTrade::Risk::Lists::ImportCSV.call(
        csv: csv("denylist,email,d15-audit-import-#{suffix}@example.com,,bulk"), store: store, actor: 'system'
      )

      audit = PallasTrade::AuditLog.where(action: 'risk_list_imported').order(:id).last
      expect(audit).to be_present
      expect(audit.after['created']).to eq(1)
      expect(audit.after.to_json).not_to include("d15-audit-import-#{suffix}@example.com")
    end
  end

  describe 'Risk::Lists::Export (AC-003)' do
    it 'exports the filtered rows and round-trips through import unchanged' do
      PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email',
                                            value: "d15-export-#{suffix}@example.com", store: store,
                                            expires_at: '2026-12-31', reason: 'export me', actor: 'system')
      PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'ip',
                                            value: '198.51.100.7', store: store, actor: 'system')

      exported = PallasTrade::Risk::Lists::Export.call(store: store, subject_type: 'email', actor: 'system')
      expect(exported).to be_success
      lines = exported.value[:csv].lines
      expect(lines.first.strip).to eq('list_type,subject_type,value,expires_at,reason')
      expect(exported.value[:count]).to eq(1)
      expect(lines[1]).to include("d15-export-#{suffix}@example.com")

      reimport = PallasTrade::Risk::Lists::ImportCSV.call(csv: exported.value[:csv], store: store, actor: 'system')
      expect(reimport.value[:created]).to eq(0)
      expect(reimport.value[:updated]).to eq(1)
      expect(reimport.value[:errors]).to be_empty
    end

    it 'audits the export without storing values' do
      PallasTrade::Risk::Lists::Upsert.call(list_type: 'allowlist', subject_type: 'email',
                                            value: "d15-export-audit-#{suffix}@example.com", store: store, actor: 'system')
      PallasTrade::Risk::Lists::Export.call(store: store, list_type: 'allowlist', actor: 'system')

      audit = PallasTrade::AuditLog.where(action: 'risk_list_exported').order(:id).last
      expect(audit).to be_present
      expect(audit.after['count']).to be >= 1
      expect(audit.after.to_json).not_to include("d15-export-audit-#{suffix}@example.com")
    end
  end
end
