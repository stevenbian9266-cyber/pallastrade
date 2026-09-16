# frozen_string_literal: true

# 商品合并台账（D-3 切片1, PRD-20260916-catalog-d3-product-merge）。
#
# 一行 = 一次合并：谁把哪个商品合并进了哪个主商品、搬了哪些行、跳过了什么、建立了哪些 redirect。
# 撤销（`Products::UndoMerge`）只读这张表，因此「撤销什么」永远等于「当时搬了什么」——
# 不依赖任何事后推断。
class PallasTrade::ProductMerge < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  has_prefix_id :pmg # PallasTrade-specific: product merge

  SECTIONS = %w[variants master_stock reviews media classifications promotions].freeze

  belongs_to :store, class_name: 'PallasTrade::Store'
  # 被合并商品在合并后处于**软删**状态，主商品也可能被再次合并 —— 关联必须带
  # `with_deleted`，否则撤销与台账展示都拿不到这两条记录。
  belongs_to :survivor, -> { with_deleted }, class_name: 'PallasTrade::Product'
  belongs_to :absorbed, -> { with_deleted }, class_name: 'PallasTrade::Product'

  validates :survivor, :absorbed, :store, presence: true
  validate :survivor_and_absorbed_must_differ

  # 未撤销的合并（partial unique 索引保证每个 absorbed 至多一条）
  scope :active, -> { where(undone_at: nil) }
  scope :undone, -> { where.not(undone_at: nil) }

  def self.active_for(absorbed) = active.find_by(absorbed_id: absorbed.id)

  def undone? = undone_at.present?

  # @param section [Symbol, String] one of {SECTIONS}
  # @return [Array<Integer>] ids moved by this merge for that section
  def moved_ids(section) = Array(moved[section.to_s]).map(&:to_i)

  # @return [Array<Hash>] skipped items (`{ 'section' =>, 'id' =>, 'label' =>, 'reason' => }`)
  def skipped_items = Array(skips)

  private

  def survivor_and_absorbed_must_differ
    return if survivor.blank? || absorbed.blank? || survivor.id != absorbed.id

    errors.add(:absorbed, 'must differ from the survivor')
  end
end
