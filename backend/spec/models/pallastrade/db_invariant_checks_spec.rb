# frozen_string_literal: true

require 'rails_helper'

# CORE-P5-6（2026-09-06）：首层 DB 金额不变量 —— 约束存在性回归（PG）
RSpec.describe 'DB invariant checks (CORE-P5-6)', type: :model do
  def check_names(table)
    ActiveRecord::Base.connection.select_values(<<~SQL, 'SCHEMA')
      SELECT pg_constraint.conname
      FROM pg_constraint
      JOIN pg_class ON pg_class.oid = pg_constraint.conrelid
      JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
      WHERE pg_namespace.nspname = 'public'
        AND pg_class.relname = '#{table}'
        AND pg_constraint.contype = 'c'
    SQL
  end

  def column_nullable?(table, column)
    ActiveRecord::Base.connection
                      .columns(table)
                      .find { |col| col.name == column }
                      .null
  end

  it 'enforces amount >= 0 on commerce_transactions' do
    expect(check_names('pallastrade_commerce_transactions'))
      .to include('pt_commerce_transactions_amount_non_negative')
  end

  it 'enforces non-negative authorized/captured/refunded on payment_splits' do
    names = check_names('pallastrade_payment_splits')
    expect(names).to include(
      'pt_payment_splits_authorized_non_negative',
      'pt_payment_splits_captured_non_negative',
      'pt_payment_splits_refunded_non_negative'
    )
  end

  it 'enforces amount_snapshot >= 0 and NOT NULL on transaction_orders' do
    expect(check_names('pallastrade_transaction_orders'))
      .to include('pt_transaction_orders_amount_snapshot_non_negative')
    expect(column_nullable?('pallastrade_transaction_orders', 'amount_snapshot')).to be(false)
  end
end
