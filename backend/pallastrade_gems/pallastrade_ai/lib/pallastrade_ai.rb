# frozen_string_literal: true

require 'pallastrade_core'
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
