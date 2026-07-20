module PallasTrade
  # STI base for order routing rules. Subclasses live in
  # app/models/spree/order_routing/rules/ and implement #rank(order, locations).
  #
  # Plugins extend the engine by defining a new subclass:
  #
  #   class AcmeFresh::OrderRouting::RefrigeratedRule < PallasTrade::OrderRoutingRule
  #     preference :max_temp_c, :integer, default: 4
  #
  #     def rank(order, locations)
  #       # ... return Array<LocationRanking>
  #     end
  #   end
  #
  # See docs/plans/6.0-order-routing.md.
  class OrderRoutingRule < PallasTrade.base_class
    self.table_name = 'pallastrade_pallastrade_order_routing_rules'

    # `rank` is integer (lower = better) when the rule has an opinion,
    # nil to abstain (the reducer skips abstaining rankings).
    LocationRanking = Struct.new(:location, :rank, keyword_init: true)

    has_prefix_id :orule

    include PallasTrade::SingleStoreResource

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :channel, class_name: 'PallasTrade::Channel'

    attribute :active, :boolean, default: true

    validates :type, :channel, presence: true
    validates :position, presence: true, numericality: { only_integer: true }
    validate :channel_belongs_to_store

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position) }
    scope :for_channel, ->(channel) { where(channel_id: channel.id) }

    acts_as_list scope: :channel_id

    self.whitelisted_ransackable_attributes = %w[type position active store_id channel_id]

    validate :type_must_be_registered

    # Subclasses override. Returns an Array<LocationRanking> — one per location,
    # with rank=nil to abstain.
    #
    # @param order     [PallasTrade::Order]
    # @param locations [Array<PallasTrade::StockLocation>]
    # @return [Array<LocationRanking>]
    def rank(_order, _locations)
      raise NotImplementedError, "#{self.class} must implement #rank(order, locations)"
    end

    private

    # The +type+ presence validation already covers blank; here we only reject
    # a present-but-unregistered STI type so arbitrary class names can't be
    # persisted via the +type+ column.
    def type_must_be_registered
      return if type.blank?
      return if PallasTrade.order_routing.rules.any? { |rule| rule.to_s == type }

      errors.add(:type, PallasTrade.t(:invalid_order_routing_rule, scope: [:errors, :messages], default: 'is not a registered order routing rule'))
    end

    def channel_belongs_to_store
      return if channel.nil? || store_id.nil?
      return if channel.store_id == store_id

      errors.add(:channel, PallasTrade.t('errors.messages.channel_store_mismatch'))
    end
  end
end
