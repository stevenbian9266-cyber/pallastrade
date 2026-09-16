module PallasTrade
  module Api
    module V3
      module Store
        # Review photo presign (PRD-20260916-catalog-batch-f1-reviews FR-004).
        #
        # Mirrors `Admin::DirectUploadsController` but requires a customer JWT:
        # the created blob is tagged with the uploader's id so that the review
        # endpoint can reject attaching somebody else's upload.
        class DirectUploadsController < Store::BaseController
          prepend_before_action :require_authentication!

          # POST /api/v3/store/direct_uploads
          def create
            blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_params)
            blob.update!(
              metadata: blob.metadata.merge(
                PallasTrade::Review::IMAGE_UPLOADER_METADATA_KEY => current_user.id
              )
            )

            render json: {
              direct_upload: {
                url: blob.service_url_for_direct_upload,
                headers: blob.service_headers_for_direct_upload
              },
              signed_id: blob.signed_id
            }, status: :created
          end

          private

          def blob_params
            params.require(:blob).permit(:filename, :byte_size, :checksum, :content_type).to_h.symbolize_keys
          end
        end
      end
    end
  end
end
