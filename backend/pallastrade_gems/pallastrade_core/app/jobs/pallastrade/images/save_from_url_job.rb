require 'open-uri'
require 'openssl'
require 'marcel'
require 'ssrf_filter'
require 'stringio'
require 'tempfile'

module PallasTrade
  module Images
    class InvalidRemoteImageError < StandardError; end

    class SaveFromUrlJob < ::PallasTrade::BaseJob
      SAMPLE_IMAGE_SCHEME = 'pallastrade-sample'
      SAMPLE_IMAGE_HOST = 'demo-images'
      DownloadedResponse = Struct.new(:code, :body)

      queue_as PallasTrade.queues.images
      retry_on ActiveRecord::RecordInvalid, wait: :polynomially_longer, attempts: PallasTrade::Config.images_save_from_url_job_attempts.to_i
      discard_on ActiveRecord::RecordNotFound
      discard_on URI::InvalidURIError
      discard_on SsrfFilter::Error
      discard_on InvalidRemoteImageError

      def perform(viewable_id, viewable_type, external_url, external_id = nil, position = nil, link_variant_id = nil)
        viewable = viewable_type.safe_constantize.find(viewable_id)

        PallasTrade::Image.ensure_metafield_definition_exists!(PallasTrade::Image::EXTERNAL_URL_METAFIELD_KEY)

        external_url = external_url.strip
        external_id = external_id.to_s.downcase.strip if external_id.present?

        image = find_or_initialize_image(viewable, external_url, external_id)

        image.set_default_values_for_import if image.new_record? && image.respond_to?(:set_default_values_for_import)

        return if image.skip_import?

        image.restore if image.respond_to?(:deleted?) && image.deleted?
        image.position = position if position.present?

        # don't re-download the image if it's already been downloaded
        # still trigger save! if position has changed
        if image_already_saved?(image, external_url)
          image.save!
          link_to_variant(image, link_variant_id)
          return
        end

        download_and_attach_image(external_url, image, external_id)
        link_to_variant(image, link_variant_id)
      rescue ActiveStorage::IntegrityError => e
        raise e unless Rails.env.test?
      end

      private

      def download_and_attach_image(external_url, image, external_id)
        max_size = PallasTrade::Config.max_image_download_size

        response = fetch_image(external_url)

        status = response.code.to_i
        unless status.between?(200, 299)
          raise InvalidRemoteImageError, %(Remote image returned HTTP #{status}: #{external_url})
        end

        body = response.body.to_s.b
        raise InvalidRemoteImageError, %(Remote image response was empty: #{external_url}) if body.empty?
        if body.bytesize > max_size
          raise InvalidRemoteImageError, %(Image file size exceeds the maximum allowed size of #{max_size} bytes)
        end

        uri = URI.parse(external_url)
        filename = File.basename(uri.path)
        filename = 'image' if filename.blank?
        # Do not pass the filename here: Marcel treats the extension as a
        # fallback, which would accept a text/HTML error body from a `.webp`
        # URL. Remote data must identify as an image from its bytes alone.
        content_type = Marcel::MimeType.for(StringIO.new(body))
        unless content_type&.start_with?('image/')
          content_type_label = content_type.present? ? content_type : 'unknown type'
          raise InvalidRemoteImageError, %(Remote response is not an image (#{content_type_label}): #{external_url})
        end

        tempfile = Tempfile.new(['pallastrade_image', File.extname(uri.path)], binmode: true)

        begin
          tempfile.write(body)
          tempfile.rewind

          image.attachment.attach(io: tempfile, filename: filename, content_type: content_type)
          image.external_url = external_url
          image.external_id = external_id if external_id.present? && image.respond_to?(:external_id)
          image.save!
        ensure
          tempfile.close
          tempfile.unlink
        end
      end

      # Packaged demo images make sample data deterministic and keep private
      # repositories, external DNS, and outbound proxies out of the seed path.
      # Every other scheme continues through SsrfFilter.
      def fetch_image(external_url)
        uri = URI.parse(external_url)
        return fetch_sample_image(uri) if uri.scheme == SAMPLE_IMAGE_SCHEME

        SsrfFilter.get(
          external_url,
          headers: {
            'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept' => 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            'Accept-Language' => 'en-US,en;q=0.9',
            'Cache-Control' => 'no-cache',
            'Pragma' => 'no-cache'
          },
          http_options: {
            read_timeout: 60,
            open_timeout: 30
          }
        )
      end

      def fetch_sample_image(uri)
        filename = File.basename(uri.path)
        valid_path = uri.host == SAMPLE_IMAGE_HOST &&
                     uri.path == '/' + filename &&
                     filename.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/) &&
                     uri.query.nil? && uri.fragment.nil?
        unless valid_path
          raise InvalidRemoteImageError, %(Invalid packaged sample image URL: #{uri})
        end

        path = PallasTrade::Core::Engine.root.join('db', 'sample_data', 'images', filename)
        unless path.file?
          raise InvalidRemoteImageError, %(Packaged sample image does not exist: #{filename})
        end

        DownloadedResponse.new('200', path.binread)
      end

      def image_already_saved?(image, external_url)
        image.persisted? && image.attachment.attached? && image.external_url.present? && external_url == image.external_url
      end

      # `Product#images` delegates to the master variant (legacy alias) — use
      # `Product#media` so 5.5 product-level uploads don't get re-pinned to master.
      def viewable_assets(viewable)
        viewable.is_a?(PallasTrade::Product) ? viewable.media : viewable.images
      end

      def image_scope(viewable)
        scope = viewable_assets(viewable)
        scope.respond_to?(:with_deleted) ? scope.with_deleted : scope
      end

      def find_or_initialize_image(viewable, external_url, external_id = nil)
        if external_id.present? && viewable.respond_to?(:external_id)
          image_scope(viewable).find_or_initialize_by(external_id: external_id)
        else
          image_scope(viewable).with_external_url(external_url).first || viewable_assets(viewable).new
        end
      end

      def link_to_variant(image, variant_id)
        return if variant_id.blank?
        return unless image.persisted? && image.viewable_type == 'PallasTrade::Product'

        PallasTrade::VariantMedia.find_or_create_by(variant_id: variant_id, media_id: image.id)
      end
    end
  end
end
