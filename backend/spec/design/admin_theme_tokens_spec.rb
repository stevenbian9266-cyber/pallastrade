# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层
#
# B6-1 设计 token 契约：品牌色阶 / 语义 token / 密度双档 + 组件零直引 + WCAG AA 对比度。
# 纯文件断言（无 DB、无浏览器），秒级 —— 供 verifier `admin-theme-rspec` 使用。
RSpec.describe 'Admin design tokens (B6-1)' do
  ADMIN_ROOT = Rails.root.join('pallastrade_gems/pallastrade_admin')
  THEME_CSS = ADMIN_ROOT.join('app/assets/tailwind/pallastrade/admin/base/_theme.css')
  COMPONENTS_DIR = ADMIN_ROOT.join('app/assets/tailwind/pallastrade/admin/components')
  LAYOUTS = %w[admin admin_wizard minimal].map { |n| ADMIN_ROOT.join("app/views/layouts/pallastrade/#{n}.html.erb") }

  def theme_css = @theme_css ||= File.read(THEME_CSS)

  def token(name) = theme_css[/--#{Regexp.escape(name)}:\s*([^;]+);/, 1]&.strip

  # WCAG 2.1 相对亮度 / 对比度（独立实现，非引用生产代码）
  def relative_luminance(hex)
    channels = [1, 3, 5].map do |i|
      v = hex[i, 2].to_i(16) / 255.0
      v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4
    end
    (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
  end

  def contrast(hex_a, hex_b)
    a = relative_luminance(hex_a)
    b = relative_luminance(hex_b)
    ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05)
  end

  describe '品牌色阶' do
    it 'defines the full primary and accent scales derived from the brand colors' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-001
      (50..950).step(1).each do |step|
        next unless [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950].include?(step)

        expect(token("color-primary-#{step}")).to match(/\A#[0-9A-F]{6}\z/), "primary-#{step} 缺失或非法"
        expect(token("color-accent-#{step}")).to match(/\A#[0-9A-F]{6}\z/), "accent-#{step} 缺失或非法"
      end
    end

    it 'points the legacy --color-primary alias at the brand primary step' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-001
      expect(theme_css).to match(/--color-primary:\s*var\(--color-primary-600\)/)
    end

    it 'keeps the accent scale defined but unused (decision: define only, enable in B6-2)' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-001
      usages = Dir[COMPONENTS_DIR.join('*.css')].sum { |f| File.read(f).scan(/accent-/).size }
      expect(usages).to eq(0)
    end
  end

  describe '语义 token' do
    it 'defines the nine semantic tokens' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-002
      %w[
        color-surface color-surface-muted color-background color-border color-border-strong
        color-text color-text-muted color-text-subtle color-focus-ring
      ].each do |name|
        expect(token(name)).to be_present, "缺少语义 token --#{name}"
      end
    end
  end

  describe '密度变量与档位' do
    it 'defines the eight density variables with compact defaults' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-003
      %w[
        admin-density-row-padding-y admin-density-row-padding-x admin-density-control-height
        admin-density-control-padding-x admin-density-label-gap admin-density-section-gap
        admin-density-font-size-base admin-density-line-height-base
      ].each do |name|
        expect(token(name)).to be_present, "缺少密度变量 --#{name}"
      end
    end

    it 'overrides at least five variables for the comfortable density' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-003
      block = theme_css[/:root\[data-admin-density="comfortable"\]\s*\{(.+?)\}/m, 1]
      expect(block).to be_present, '缺少 comfortable 密度覆盖块'
      overridden = block.scan(/--admin-density-[a-z-]+:/).uniq
      expect(overridden.size).to be >= 5
    end

    it 'marks every admin layout with the default density attribute' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-004
      LAYOUTS.each do |layout|
        # 注意：`<html …>` 行内含 ERB（`<%= html_dir %>`），因此不能用 [^>]* 匹配
        expect(File.read(layout)).to match(/<html[^\n]*data-admin-density="compact"/), "#{layout.basename} 未输出默认密度"
      end
    end
  end

  describe '主色消费点' do
    let(:buttons) { File.read(COMPONENTS_DIR.join('_buttons.css')) }
    let(:navigation) { File.read(COMPONENTS_DIR.join('_navigation.css')) }

    it 'routes primary buttons, secondary buttons and nav states through brand tokens' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-005
      expect(buttons).to include('bg-primary-600').and include('bg-primary-700')
      expect(buttons).to include('text-primary-900').and include('bg-primary-50')
      expect(buttons).to include('ring-focus-ring')
      expect(navigation).to include('text-primary-700').and include('bg-primary-50')
    end

    it 'leaves no direct Tailwind palette usage on the primary semantics' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-005
      expect(buttons).not_to match(/bg-zinc-950|border-zinc-950|bg-zinc-800|border-zinc-800/)
      expect(buttons).not_to match(/bg-blue-50|bg-blue-100|text-blue-900/)
      expect(navigation).not_to include('text-zinc-950')
    end
  end

  describe '可访问性契约（WCAG AA）' do
    def hex_of(name) = token(name)

    it 'meets 4.5:1 for body/muted text on surfaces' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-007
      expect(contrast(hex_of('color-text'), hex_of('color-surface'))).to be >= 4.5
      expect(contrast(hex_of('color-text-muted'), hex_of('color-surface'))).to be >= 4.5
      expect(contrast(hex_of('color-text-subtle'), hex_of('color-surface'))).to be >= 4.5
    end

    it 'meets 4.5:1 for white text on the brand primary button colour' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-007
      expect(contrast('#FFFFFF', hex_of('color-primary-600'))).to be >= 4.5
      expect(contrast(hex_of('color-primary-600'), '#FFFFFF')).to be >= 4.5
    end

    it 'meets 3:1 for the focus ring against the surface' do
      # PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 AC-007
      expect(contrast(hex_of('color-focus-ring'), hex_of('color-surface'))).to be >= 3.0
    end
  end
end
