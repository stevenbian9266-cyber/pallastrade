# frozen_string_literal: true

# F-5（PRD-20260916-catalog-batch-f5-helpful-vote FR-001）——评论「有用」投票。
#
# 为什么需要这张表：评论已有评分/文本/审核/图片，但**读者无法表达「这条有用」**，
# 优质长评没有可以排序的信号（F-4 已把 `most_helpful` 显式后置到本批）。
#
# 一人一票由**唯一索引**保证（不是仅靠模型校验）：双击、重试、并发都不会翻倍计数。
# `store_id` 冗余写入，使跨店隔离与按店统计都不需要 JOIN 评论表。
#
# 只新增表/索引 + 1 个计数列，不回填、不改既有列。
class CreatePallasTradeReviewVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :pallastrade_review_votes do |t|
      t.bigint :review_id, null: false
      t.bigint :user_id, null: false
      t.bigint :store_id, null: false
      t.timestamps
    end

    # 幂等：一个客户对一条评论只有一票（并发由唯一键兜底）
    add_index :pallastrade_review_votes, %i[review_id user_id],
              unique: true, name: 'idx_review_votes_identity'
    add_index :pallastrade_review_votes, :review_id
    add_index :pallastrade_review_votes, :user_id
    add_index :pallastrade_review_votes, %i[store_id review_id]

    # 计数器列：列表页每行都要读票数，绝不能变成 N 次 COUNT(*)。
    # 默认 0 + NOT NULL，存量评论无需回填。
    add_column :pallastrade_reviews, :helpful_votes_count, :integer, default: 0, null: false
  end
end
