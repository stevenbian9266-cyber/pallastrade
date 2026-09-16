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

          # Photo payloads the API refuses; mapped to 422 with a stable code.
          class ImageError < StandardError
            attr_reader :code

            def initialize(code)
              @code = code
              super(code)
            end
          end

          DEFAULT_LIMIT = 10
          MAX_LIMIT = 100
          MAX_IMAGES = PallasTrade::Review::MAX_IMAGES

          # GET /api/v3/store/products/:product_id/reviews
          #
          # F-1 (PRD-20260916-catalog-batch-f1-reviews FR-002/FR-003): paginated
          # (`page`/`limit`, default 10 / max 100) with `meta.rating_distribution`
          # next to the usual v3 pagination keys. Only approved reviews are
          # exposed — and therefore only their photos.
          def index
            product = current_store.products.find_by_param!(params[:product_id])
            @pagy, reviews = pagy(approved_reviews(product), limit: limit_param, page: page_param)

            render json: {
              data: serialize_collection(reviews),
              meta: collection_meta(product)
            }
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
            attach_images(review)

            if review.save
              render json: serialize_resource(review), status: :created
            else
              render_errors(review.errors)
            end
          rescue ImageError => e
            render_error(code: e.code, message: 'review photos rejected', status: 422)
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

          private

          def approved_reviews(product)
            product.reviews.approved
                   .includes(:user, images_attachments: :blob)
                   .order(created_at: :desc, id: :desc)
          end

          # Same keys every other v3 list endpoint returns, plus the distribution.
          def collection_meta(product)
            {
              page: @pagy.page,
              limit: @pagy.limit,
              count: @pagy.count,
              pages: @pagy.pages,
              from: @pagy.from,
              to: @pagy.to,
              in: @pagy.in,
              previous: @pagy.previous,
              next: @pagy.next,
              rating_distribution: rating_distribution(product)
            }
          end

          # One aggregate query over approved reviews — the same population the
          # product serializer reports as `average_rating` / `review_count`.
          def rating_distribution(product)
            counts = product.reviews.approved.group(:rating).count
            (1..5).to_h { |star| [star.to_s, counts[star].to_i] }
          end

          def page_param
            [params[:page].to_i, 1].max
          end

          def limit_param
            requested = params[:limit].to_i
            requested = DEFAULT_LIMIT if requested <= 0
            [requested, MAX_LIMIT].min
          end

          # Attaches photos this customer uploaded through the presign endpoint.
          # The signed ids are verified and the blob must carry this customer's
          # uploader tag, so a leaked signed id cannot be attached by someone else.
          def attach_images(review)
            signed_ids = Array(params[:images]).compact_blank
            return if signed_ids.empty?

            raise ImageError, 'review_image_limit_exceeded' if signed_ids.size > MAX_IMAGES

            review.images.attach(signed_ids.map { |signed_id| upload_owned_by_current_user(signed_id) })
          end

          def upload_owned_by_current_user(signed_id)
            blob = ActiveStorage::Blob.find_signed!(signed_id)
            uploader = blob.metadata[PallasTrade::Review::IMAGE_UPLOADER_METADATA_KEY].to_i

            raise ImageError, 'review_image_not_owned' unless uploader.positive? && uploader == current_user.id

            blob
          rescue ActiveSupport::MessageVerifier::InvalidSignature
            raise ImageError, 'review_image_invalid'
          end
        end
      end
    end
  end
end
