module PallasTrade
  module Api
    module V3
      module Store
        # Product reviews (P0-4).
        #
        # Public read: approved reviews for a product (no auth).
        # Write: signed-in customers submit a review (status → pending).
        class ReviewsController < Store::BaseController
          # POST /api/v3/store/products/:product_id/reviews — requires a customer JWT
          prepend_before_action :require_authentication!, only: [:create]

          # GET /api/v3/store/products/:product_id/reviews
          def index
            product = current_store.products.find_by_param!(params[:product_id])
            reviews = product.reviews.approved
                            .includes(:user)
                            .order(created_at: :desc)
                            .limit(100)

            render json: serialize_collection(reviews)
          rescue ActiveRecord::RecordNotFound
            render_error(code: ERROR_CODES[:record_not_found], message: 'product not found', status: :not_found)
          end

          # POST /api/v3/store/products/:product_id/reviews
          def create
            product = current_store.products.find_by_param!(params[:product_id])

            review = product.reviews.build(review_params)
            review.store = current_store
            review.user = current_user
            review.status = 'pending'
            review.verified_purchase = verified_purchase?(product)

            if review.save
              render json: serialize_resource(review), status: :created
            else
              render_errors(review.errors)
            end
          rescue ActiveRecord::RecordNotFound
            render_error(code: ERROR_CODES[:record_not_found], message: 'product not found', status: :not_found)
          end

          protected

          def serializer_class
            PallasTrade.api.review_serializer
          end

          def review_params
            params.permit(:rating, :title, :body)
          end

          # A customer is a verified purchaser when they have a completed order
          # that includes this product's variants.
          def verified_purchase?(product)
            current_user.present? &&
              product.completed_orders.where(user: current_user).exists?
          end
        end
      end
    end
  end
end
