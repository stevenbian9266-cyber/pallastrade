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

          # F-4 (PRD-20260916-catalog-batch-f4-review-sorting FR-001/FR-002):
          # whitelisted orderings. Every one of them ends with `id DESC` so two
          # reviews sharing a rating *and* a timestamp still have a deterministic
          # order — without that, paging could repeat or skip rows.
          #
          # F-5 adds `most_helpful` on top of F-4's list (same whitelist, same
          # fallback, same tie-break): the vote count is a counter-cache column, so
          # ordering by it stays a single indexed sort.
          DEFAULT_SORT = 'newest'
          SORT_ORDERS = {
            'newest' => { created_at: :desc, id: :desc },
            'highest_rating' => { rating: :desc, created_at: :desc, id: :desc },
            'lowest_rating' => { rating: :asc, created_at: :desc, id: :desc },
            'most_helpful' => { helpful_votes_count: :desc, id: :desc }
          }.freeze

          # GET /api/v3/store/products/:product_id/reviews
          #
          # F-1 (PRD-20260916-catalog-batch-f1-reviews FR-002/FR-003): paginated
          # (`page`/`limit`, default 10 / max 100) with `meta.rating_distribution`
          # next to the usual v3 pagination keys. Only approved reviews are
          # exposed — and therefore only their photos.
          #
          # F-4: `sort` (whitelisted, unknown values fall back to the default)
          # and `meta.sort` echoing the value that was actually applied.
          def index
            product = current_store.products.find_by_param!(params[:product_id])
            @pagy, reviews = pagy(approved_reviews(product), limit: limit_param, page: page_param)
            # F-5: one query for the whole page tells the serializer which of these
            # reviews the signed-in caller already voted helpful.
            @voted_review_ids = voted_review_ids_for(reviews)

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

          # F-5: the vote set is only known on `index`; every other response keeps
          # `helpful_voted` as nil ("not asked") instead of inventing a `false`.
          def serializer_params
            super.merge(voted_review_ids: @voted_review_ids)
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
                   .order(SORT_ORDERS.fetch(sort_param))
          end

          # Same keys every other v3 list endpoint returns, plus the distribution
          # (F-1) and the ordering that was applied (F-4).
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
              rating_distribution: rating_distribution(product),
              sort: sort_param
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

          # Unknown / blank orderings fall back to the default instead of
          # erroring: the whitelist is an internal detail, not a contract the
          # storefront (or a scraper) should be able to probe through 4xx codes.
          def sort_param
            requested = params[:sort].to_s
            SORT_ORDERS.key?(requested) ? requested : DEFAULT_SORT
          end

          # F-5: which of *this page's* reviews the caller already voted helpful.
          # Scoped by store so a vote cast in another store can never show up here.
          def voted_review_ids_for(reviews)
            return [] if current_user.blank? || reviews.empty?

            PallasTrade::ReviewVote
              .where(store_id: current_store.id, user_id: current_user.id, review_id: reviews.map(&:id))
              .pluck(:review_id)
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
