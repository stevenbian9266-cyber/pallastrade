# frozen_string_literal: true

# 「有用」投票（F-5, PRD-20260916-catalog-batch-f5-helpful-vote）。
#
# 一个客户对一条评论只有一票：**唯一索引**是权威，模型校验只负责给出人类可读的错误
# （双击 / 重试 / 并发都不会抬高计数）。
# 投票始终带身份：面向商城的只有聚合值（票数）与调用者自己的状态，**永远不暴露投票者是谁**。
class PallasTrade::ReviewVote < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  has_prefix_id :rv # PallasTrade-specific: review vote（`rev` 已属于 Review）

  belongs_to :review, class_name: 'PallasTrade::Review', counter_cache: :helpful_votes_count
  belongs_to :user, class_name: "::#{PallasTrade.user_class}"
  belongs_to :store, class_name: 'PallasTrade::Store'

  validates :review, :user, :store, presence: true
  validates :review_id, uniqueness: { scope: :user_id }

  validate :voter_is_not_the_author
  validate :review_is_approved

  private

  # 给自己投票不是信号，是刷分。
  def voter_is_not_the_author
    return if review.blank? || user.blank? || review.user_id != user_id

    errors.add(:user, 'cannot vote for their own review')
  end

  # 只有已审核评论对读者可见，因此投票也只能落在读者真正看得到的东西上。
  def review_is_approved
    return if review.blank? || review.approved?

    errors.add(:review, 'must be approved before it can be voted on')
  end
end
