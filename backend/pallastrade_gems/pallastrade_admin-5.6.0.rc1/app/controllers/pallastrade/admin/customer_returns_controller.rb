module PallasTrade
  module Admin
    class CustomerReturnsController < ResourceController
      add_breadcrumb_icon 'receipt-refund'
      add_breadcrumb PallasTrade.t(:returns), :admin_customer_returns_path
      add_breadcrumb PallasTrade.t(:customer_returns), :admin_customer_returns_path

      def index; end
    end
  end
end
