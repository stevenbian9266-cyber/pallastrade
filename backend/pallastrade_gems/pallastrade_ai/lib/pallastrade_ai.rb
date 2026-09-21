# frozen_string_literal: true

require 'pallastrade_core'
# PALLAS-CUSTOM: 收敛切片 5 修复（2026-09-21）—— 显式 require 外部依赖。
# 背景：本 gem 的 `ExecuteRunJob` / `Providers::Base` / `Middleware::SsrfProtection` 在**类体**里引用
# `Faraday::*` 常量，而 Faraday 不是 Rails autoload 的常量，必须在 eager_load 之前被 require。
# 此前一直由已下线的 `pallastrade_adyen` / `pallastrade_paypal_checkout` 传递 require 侥幸生效；
# 那两个 gem 移除后 `zeitwerk:check` / eager_load 立即报
# `uninitialized constant PallasTrade::AI::ExecuteRunJob::Faraday`。
# gemspec 早已声明 faraday + faraday-retry 为 runtime 依赖，这里补上对应的 require。
require 'faraday'
require 'faraday/retry'
require 'pallastrade_ai/version'
require 'pallastrade_ai/configuration'
require 'pallastrade/ai'
require 'pallastrade_ai/engine'

module PallasTradeAI
  # Queue names for AI jobs.
  mattr_accessor :interactive_queue, :batch_queue

  def self.interactive_queue
    @@interactive_queue ||= :pallastrade_ai_interactive
  end

  def self.batch_queue
    @@batch_queue ||= :pallastrade_ai_batch
  end

  # Convenience accessor under PallasTrade::AI namespace.
  def self.table_name_prefix
    'pallastrade_ai_'
  end
end
