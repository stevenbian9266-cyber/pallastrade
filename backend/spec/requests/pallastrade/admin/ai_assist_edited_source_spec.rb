# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-ai-edited-before-save AC-006 AC-007 AC-008 AC-009
# PRD-20260916-catalog-ai-acceptance-audit AC-009
#
# 两个 PRD 共用同一组源级断言：后者（较早）的 AC-009 描述的就是这段 JS 的容错契约
# ——“accept()/discard() 均触发上报；上报抛错时表单写入与 UI 状态不变”，
# 而本文件已把它钉在源码上（见 “swallows report failures so the save is never blocked”
# 与 “keeps the report alive across the navigation” 两例）。此处只补标记，不重复写同义断言。
#
# 本项目**没有**前端 JS 单测基建（无 jest/vitest），而“采纳后被编辑”的核心风险是
# **误报**与**阻断保存**。与其为此引入一套新测试基建，这里对控制器源码断言四个
# 必须存在的行为 —— 它挡不住所有回归，但能挡住最真实的三类：
#   1) 快照取在写值之前 → 每次都误报 edited
#   2) 用“表单被碰过吗”代替值比较 → 改别的字段也误报
#   3) 去掉 keepalive / try-catch → 观测把保存搞坏
# 这是**有取舍的**做法，已在 PRD §8/D5 如实记录。
RSpec.describe 'AI assist controller — edited-before-save contract' do
  let(:source) do
    File.read(
      Rails.root.join('pallastrade_gems/pallastrade_admin/app/javascript/pallastrade/admin/controllers/ai_assist_controller.js')
    )
  end

  # AC-006 相关的正确性前提：快照必须在 writeValue 之后取。
  it 'captures the draft after writing it into the form' do
    capture_at = source.index('this.captureDraft(runId, written)')
    write_at = source.index('this.writeValue(this.fieldTarget, this.pending.text)')

    expect(capture_at).to be_present
    expect(write_at).to be_present
    expect(capture_at).to be > write_at,
                           '快照必须在写值之后 —— 否则记的是写入前的表单值，每次保存都会误报 edited'
  end

  # AC-007 的判定依据：按**值**比较。
  it 'compares by value rather than by “the form was touched”' do
    expect(source).to include('input.value !== value')
  end

  # AC-006/007 的边界：只报一次。
  it 'clears the snapshot so it can report at most once' do
    expect(source).to match(/this\.acceptedDraft = null/)
    expect(source).to match(/this\.acceptedRunId = null/)
  end

  # AC-008：没 Accept 过就不该报。
  it 'does nothing when no draft was accepted' do
    expect(source).to match(/beforeSubmit\(\)\s*\{\s*\n\s*if \(!this\.acceptedDraft\) return/)
  end

  # AC-009：观测不得阻断保存。
  it 'keeps the report alive across the navigation' do
    expect(source).to include('keepalive: true')
  end

  it 'swallows report failures so the save is never blocked' do
    expect(source).to include('catch (_error)')
  end

  it 'only reports edited when something actually changed' do
    expect(source).to match(/if \(changed\) this\.reportAcceptance\(runId, 'edited'\)/)
  end

  it 'removes its submit listener when the controller disconnects' do
    expect(source).to include('removeEventListener')
  end
end
