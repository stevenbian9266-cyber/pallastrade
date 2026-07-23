module PallasTrade
  module CSV
    class CustomerPresenter
      include PallasTrade::CSV::MetafieldsHelper

      HEADERS = [
        'First Name',
        'Last Name',
        'Email',
        'Accepts Email Marketing',
        'Company',
        'Address 1',
        'Address 2',
        'City',
        'Province',
        'Province Code',
        'Country',
        'Country Code',
        'Zip',
        'Phone',
        'Total Spent',
        'Total Orders',
        'Tags'
      ].freeze

      def initialize(customer)
        @customer = customer
      end

      attr_accessor :customer

      def call
        csv = [
          customer.first_name,
          customer.last_name,
          customer.email,
          customer.accepts_email_marketing ? PallasTrade.t(:say_yes) : PallasTrade.t(:say_no),
          customer.address&.company,
          customer.address&.address1,
          customer.address&.address2,
          customer.address&.city,
          customer.address&.state_text,
          customer.address&.state_abbr,
          customer.address&.country&.name,
          customer.address&.country&.iso,
          customer.address&.zipcode,
          customer.phone,
          customer.amount_spent_in(PallasTrade::Store.current.default_currency),
          customer.completed_orders.count,
          customer.tag_list
        ]

        csv += metafields_for_csv(customer)

        csv
      end
    end
  end
end
