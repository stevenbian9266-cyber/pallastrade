module PallasTrade
  class Promotion < PallasTrade.base_class
    has_prefix_id :promo # PallasTrade-specific: promotion

    include PallasTrade::SingleStoreResource
    include PallasTrade::Metafields
    include PallasTrade::Metadata

    include PallasTrade::Security::Promotions if defined?(PallasTrade::Security::Promotions)
    # Multi-store sharing moved to the pallastrade_multi_store extension in 5.6.
    include PallasTrade::LegacyMultiStoreSupport unless defined?(PallasTradeMultiStore)

    publishes_lifecycle_events

    MATCH_POLICIES = %w(all any)
    UNACTIVATABLE_ORDER_STATES = ['complete', 'awaiting_return', 'returned']

    attr_reader :eligibility_errors, :generate_code

    #
    # Magic methods
    #
    normalizes :code, :path, :name, with: ->(value) { value ? value.to_s.squish.presence : nil }

    #
    # Enums
    #
    enum :kind, { coupon_code: 0, automatic: 1 }

    #
    # Associations
    #
    belongs_to :promotion_category, optional: true
    has_many :promotion_rules, autosave: true, dependent: :destroy
    alias rules promotion_rules
    has_many :promotion_actions, autosave: true, dependent: :destroy
    alias actions promotion_actions
    has_many :coupon_codes, -> { order(created_at: :asc) }, dependent: :destroy, class_name: 'PallasTrade::CouponCode'
    # PRD-20260910-promotions-promo-batch3a: 核销台账（usage_limit 的唯一口径）。
    has_many :promotion_redemptions, class_name: 'PallasTrade::PromotionRedemption',
                                     dependent: :destroy, inverse_of: :promotion
    has_many :order_promotions, class_name: 'PallasTrade::OrderPromotion'
    has_many :orders, through: :order_promotions, class_name: 'PallasTrade::Order'
    belongs_to :store, class_name: 'PallasTrade::Store'

    after_save :apply_pending_rules_and_actions, if: :pending_rules_or_actions?

    #
    # Callbacks
    #
    before_validation :set_code_to_nil, if: -> { multi_codes? || automatic? }
    before_validation :set_number_of_codes_to_nil, if: -> { automatic? || !multi_codes? }
    before_validation :set_usage_limit_to_nil, if: -> { multi_codes? }
    before_validation :set_kind
    before_validation :downcase_code, if: -> { code.present? }
    before_validation :set_starts_at_to_current_time, if: -> { starts_at.blank? }
    after_commit :generate_coupon_codes, if: -> { multi_codes? }, on: [:create, :update]
    after_commit :remove_coupons, on: :update
    before_destroy :not_used?

    #
    # Validations
    #
    validates_associated :rules
    validates :name, presence: true
    validates :store, presence: true, unless: -> { PallasTrade::Config[:disable_store_presence_validation] }
    validates :usage_limit, numericality: { greater_than: 0, allow_nil: true }
    validates :description, length: { maximum: 255 }, allow_blank: true
    validate :expires_at_must_be_later_than_starts_at, if: -> { starts_at && expires_at }
    validates :code, presence: true, if: -> { coupon_code? && !multi_codes? }
    # Store-scoped single-code uniqueness (PRD-20260909-promo-batch1 AC-P3-1).
    # Mirrors the DB functional unique index (store_id, lower(btrim(code))).
    validate :code_unique_in_store, if: -> { coupon_code? && !multi_codes? && code.present? }
    validates :number_of_codes, numericality: {
      only_integer: true,
      greater_than: 0,
      less_than_or_equal_to: PallasTrade::Config.coupon_codes_total_limit
    }, if: -> { multi_codes? }

    #
    # Scopes
    #
    scope :expired, -> { where('expires_at < ?', Time.current) }
    scope :coupons, -> { where(kind: :coupon_code) }
    scope :advertised, -> { where(advertise: true) }
    scope :applied, lambda {
      joins(<<-SQL).distinct
        INNER JOIN pallastrade_order_promotions
        ON pallastrade_order_promotions.promotion_id = #{table_name}.id
      SQL
    }

    #
    # Ransack
    #
    # `name` is whitelisted so the admin global search / command palette can
    # filter via the `name_or_code_cont` predicate without a dedicated scope.
    self.whitelisted_ransackable_attributes = ['name', 'path', 'promotion_category_id', 'code', 'starts_at', 'expires_at']
    self.whitelisted_ransackable_associations = %w[coupon_codes]

    # Deterministic code lookup (PRD-20260909-promo-batch1 AC-P3-3):
    # 1) a single-code promotion matching the normalized code wins;
    # 2) otherwise a promotion that owns a matching generated CouponCode;
    # 3) ties (historical duplicates only) resolve to the most recently created.
    def self.with_coupon_code(coupon_code)
      return nil unless coupon_code.present?

      normalized = coupon_code.to_s.strip.downcase

      scoped = coupons.includes(:promotion_actions).
               where.not(pallastrade_promotion_actions: { id: nil })

      single = scoped.where(code: normalized).order(created_at: :desc, id: :desc).first
      return single if single

      scoped.
        where(id: PallasTrade::CouponCode.where(code: normalized).select(:promotion_id)).
        order(created_at: :desc, id: :desc).
        first
    end

    def self.active
      where('pallastrade_promotions.starts_at IS NULL OR pallastrade_promotions.starts_at < ?', Time.current).
        where('pallastrade_promotions.expires_at IS NULL OR pallastrade_promotions.expires_at > ?', Time.current)
    end

    def self.order_activatable?(order)
      order && !UNACTIVATABLE_ORDER_STATES.include?(order.state)
    end

    def generate_code=(generating_code)
      self.code = random_code if ActiveModel::Type::Boolean.new.cast(generating_code)
    end

    # Flat-payload writer for `rules`. See
    # {PallasTrade::TypedAssociations#assign_typed_association}.
    def rules=(rows)
      assign_typed_association(:promotion_rules, rows)
    end

    # Mirrors `rules=` for promotion actions.
    def actions=(rows)
      assign_typed_association(:promotion_actions, rows)
    end

    def pending_rules_or_actions?
      @pending_promotion_rules.present? || @pending_promotion_actions.present?
    end

    def active?
      starts_at.present? && starts_at < Time.current && (expires_at.blank? || !expired?)
    end

    def inactive?
      !active?
    end

    def expired?
      !!((starts_at && Time.current < starts_at) || (expires_at && Time.current > expires_at))
    end

    def all_codes_used?
      coupon_codes.used.count == coupon_codes.count
    end

    def activate(payload)
      order = payload[:order]
      return unless self.class.order_activatable?(order)

      payload[:promotion] = self

      # Track results from actions to see if any action has been taken.
      # Actions should return nil/false if no action has been taken.
      # If an action returns true, then an action has been taken.
      results = actions.map do |action|
        action.perform(payload)
      end
      # If an action has been taken, report back to whatever activated this promotion.
      action_taken = results.include?(true)

      if action_taken
        # connect to the order
        # create the join_table entry.
        order.promotions << self unless order.promotions.include?(self)
        order.save
      end

      action_taken
    end

    # Called when a promotion is removed from the cart
    def deactivate(payload)
      order = payload[:order]
      return unless self.class.order_activatable?(order)

      payload[:promotion] = self

      # Track results from actions to see if any action has been taken.
      # Actions should return nil/false if no action has been taken.
      # If an action returns true, then an action has been taken.
      results = actions.map do |action|
        action.revert(payload) if action.respond_to?(:revert)
      end

      # If an action has been taken, report back to whatever `d this promotion.
      action_taken = results.include?(true)

      if action_taken
        # connect to the order
        # create the join_table entry.
        order.promotions << self unless order.promotions.include?(self)
        order.save
      end

      action_taken
    end

    # called anytime order.update_with_updater! happens
    def eligible?(promotable, options = {})
      return false if expired? || usage_limit_exceeded?(promotable) || blacklisted?(promotable)

      !!eligible_rules(promotable, options)
    end

    # eligible_rules returns an array of promotion rules where eligible? is true for the promotable
    # if there are no such rules, an empty array is returned
    # if the rules make this promotable ineligible, then nil is returned (i.e. this promotable is not eligible)
    def eligible_rules(promotable, options = {})
      # Promotions without rules are eligible by default.
      return [] if rules.none?

      specific_rules = rules.select { |rule| rule.applicable?(promotable) }
      return [] if specific_rules.none?

      rule_eligibility = specific_rules.to_h do |rule|
        [rule, rule.eligible?(promotable, options)]
      end

      if match_all?
        # If there are rules for this promotion, but no rules for this
        # particular promotable, then the promotion is ineligible by default.
        unless rule_eligibility.values.all?
          @eligibility_errors = specific_rules.map(&:eligibility_errors).detect(&:present?)
          return nil
        end
        specific_rules
      else
        unless rule_eligibility.values.any?
          @eligibility_errors = specific_rules.map(&:eligibility_errors).detect(&:present?)
          return nil
        end

        [rule_eligibility.detect { |_, eligibility| eligibility }.first]
      end
    end

    def products
      rules.where(type: 'PallasTrade::Promotion::Rules::Product').map(&:products).flatten.uniq
    end

    # PRD-20260910-promotions-promo-batch3a (D4): usage_limit 读取核销台账（committed），
    # 不再依赖 Adjustment 即时统计。
    def usage_limit_exceeded?(promotable)
      return false if usage_limit.blank? || !usage_limit.positive?

      adjusted_credits_count(promotable) >= usage_limit
    end

    # 已核销计数（ledger）；当前订单自身的核销不计入，避免重算/重放时自锁。
    def adjusted_credits_count(promotable)
      count = credits_count
      return count unless promotable.is_a?(PallasTrade::Order) && promotable.persisted?

      count - promotion_redemptions.committed.where(order_id: promotable.id).count
    end

    # @deprecated 旧口径（Adjustment 统计）。保留供审计/兼容读取；
    # 业务判定请用 `credits_count`（ledger committed）。
    def credits
      Adjustment.eligible.promotion.where(source_id: actions.map(&:id))
    end

    # PRD-20260910-promotions-promo-batch3a (D4): ledger committed 计数。
    def credits_count
      promotion_redemptions.committed.count
    end

    def line_item_actionable?(order, line_item)
      if eligible? order
        rules = eligible_rules(order)
        rules.blank? || rules.send(match_all? ? :all? : :any?) do |rule|
          rule.actionable? line_item
        end
      else
        false
      end
    end

    def used_by?(user, excluded_orders = [])
      user.orders.complete.joins(:promotions).joins(:all_adjustments).
        where.not(pallastrade_orders: { id: excluded_orders.map(&:id) }).
        where(pallastrade_promotions: { id: id }).
        where(pallastrade_adjustments: { source_type: 'PallasTrade::PromotionAction', eligible: true }).any?
    end

    def name_for_order(order)
      if coupon_code?
        code_for_order(order)
      else
        name
      end.to_s.upcase
    end

    def code_for_order(order)
      if multi_codes?
        coupon_codes.find_by(order: order)&.code
      else
        code
      end
    end

    private

    def apply_pending_rules_and_actions
      flush_pending_typed_association(:promotion_rules)
      flush_pending_typed_association(:promotion_actions)
    end

    def not_used?
      return true if orders.empty?

      errors.add(:base, PallasTrade.t('promotion_already_used'))
      throw(:abort)
    end

    # Store-scoped single-code uniqueness (PRD-20260909-promo-batch1 AC-P3-1).
    # Compares against the same normalization the DB index enforces
    # (trim + downcase) so the model error and the index stay in sync.
    def code_unique_in_store
      return unless store_id.present?

      scope = PallasTrade::Promotion.
              where(store_id: store_id, kind: :coupon_code).
              where.not(multi_codes: true)
      scope = scope.where.not(id: id) if id.present?

      duplicate = scope.where('lower(btrim(code)) = ?', code.to_s.downcase).exists?
      errors.add(:code, PallasTrade.t('promotion_code_taken_in_store')) if duplicate
    end

    def set_kind
      self.kind = :coupon_code if (code.present? || (multi_codes? && number_of_codes.present?)) && kind == 'automatic'
    end

    def downcase_code
      self.code = code.downcase.strip
    end

    def set_code_to_nil
      self.code = nil
    end

    def set_usage_limit_to_nil
      self.usage_limit = nil
    end

    def set_number_of_codes_to_nil
      self.number_of_codes = nil
      self.code_prefix = nil
      self.multi_codes = false
    end

    def set_starts_at_to_current_time
      self.starts_at = Time.current
    end

    def generate_coupon_codes
      return if number_of_codes.nil?
      return if number_of_codes <= coupon_codes.count
      return unless saved_change_to_number_of_codes?

      if number_of_codes > PallasTrade::Config.coupon_codes_web_limit
        PallasTrade::CouponCodes::BulkGenerateJob.perform_later(id, number_of_codes - coupon_codes.count)
      else
        PallasTrade::CouponCodes::BulkGenerate.call(promotion: self, quantity: number_of_codes - coupon_codes.count)
      end
    end

    def remove_coupons
      return unless (previous_changes.key?('kind') && previous_changes['kind'][0] == 'coupon_code' && kind == 'automatic') ||
        (previous_changes.key?('multi_codes') && previous_changes['multi_codes'][0] == true && multi_codes == false)

      coupon_codes.where(deleted_at: nil).update_all(deleted_at: Time.current)
    end

    def blacklisted?(promotable)
      case promotable
      when PallasTrade::LineItem
        !promotable.product.promotionable?
      when PallasTrade::Order
        (promotable.item_count.positive? || promotable.line_items.any?) &&
          promotable.line_items.joins(:product).where(pallastrade_products: { promotionable: true }).none?
      end
    end

    def match_all?
      match_policy == 'all'
    end

    def expires_at_must_be_later_than_starts_at
      errors.add(:expires_at, :invalid_date_range) if expires_at < starts_at
    end

    def random_code
      loop do
        random_token = SecureRandom.hex(4)
        break random_token unless self.class.exists?(code: random_token)
      end
    end
  end
end
