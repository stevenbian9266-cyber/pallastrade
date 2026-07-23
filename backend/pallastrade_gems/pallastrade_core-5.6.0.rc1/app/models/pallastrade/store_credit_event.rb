module PallasTrade
  class StoreCreditEvent < PallasTrade.base_class
    has_prefix_id :scevt

    acts_as_paranoid

    #
    # Associations
    belongs_to :store_credit
    belongs_to :originator, polymorphic: true
    has_one :payment, -> { where(source_type: PallasTrade::StoreCredit.to_s) }, foreign_key: :response_code, primary_key: :authorization_code
    has_one :order, through: :payment

    #
    # Scopes
    scope :exposed_events, -> { where.not(action: [PallasTrade::StoreCredit::ELIGIBLE_ACTION, PallasTrade::StoreCredit::AUTHORIZE_ACTION]) }
    scope :reverse_chronological, -> { order(created_at: :desc) }

    delegate :currency, :store, to: :store_credit

    extend DisplayMoney
    money_methods :amount, :user_total_amount

    def display_action
      case action
      when PallasTrade::StoreCredit::CAPTURE_ACTION
        PallasTrade.t('store_credit.captured')
      when PallasTrade::StoreCredit::AUTHORIZE_ACTION
        PallasTrade.t('store_credit.authorized')
      when PallasTrade::StoreCredit::ALLOCATION_ACTION
        PallasTrade.t('store_credit.allocated')
      when PallasTrade::StoreCredit::ELIGIBLE_ACTION
        PallasTrade.t('store_credit.eligible')
      when PallasTrade::StoreCredit::VOID_ACTION, PallasTrade::StoreCredit::CREDIT_ACTION
        PallasTrade.t('store_credit.credit')
      end
    end

    def allocation?
      action == PallasTrade::StoreCredit::ALLOCATION_ACTION
    end

    def credit?
      action == PallasTrade::StoreCredit::CREDIT_ACTION
    end

    def captured?
      action == PallasTrade::StoreCredit::CAPTURE_ACTION
    end

    def voided?
      action == PallasTrade::StoreCredit::VOID_ACTION
    end

    def authorized?
      action == PallasTrade::StoreCredit::AUTHORIZE_ACTION
    end
  end
end
