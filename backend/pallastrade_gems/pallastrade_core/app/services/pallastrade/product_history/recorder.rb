# frozen_string_literal: true

module PallasTrade
  module ProductHistory
    # Writes the product timeline (PRD-20260915-catalog-batch-d1-product-history).
    #
    # Reuses `pallastrade_audit_logs` — no new table: the recorder snapshots the
    # tracked attributes before a write and stores only what actually changed,
    # together with the actor (admin user) that performed it.
    module Recorder
      # Attributes the merchant edits on the product form. Translatable fields are
      # read through Mobility in the current content locale.
      TRACKED_ATTRIBUTES = %w[
        name slug status description meta_title meta_description available_on discontinue_on
      ].freeze

      class << self
        # @param product [PallasTrade::Product]
        # @return [Hash] current values of the tracked attributes
        def snapshot(product)
          TRACKED_ATTRIBUTES.index_with { |attribute| product.public_send(attribute) }
        end

        # Records one product write for the timeline.
        #
        # @param action [String] e.g. 'product.created' / 'product.updated'
        # @param before [Hash, nil] snapshot taken before the write (nil for create)
        # @param metadata [Hash] extra context (`sections`, bulk counts…)
        # @return [PallasTrade::AuditLog, nil]
        def record_product(product:, action:, actor:, before: nil, metadata: {})
          after = snapshot(product)
          changed = changed_attributes(before, after)
          metadata = metadata.compact

          # An update that touched nothing (and has no extra context) is not
          # history worth keeping.
          return if update_action?(action) && changed.empty? && metadata.blank?

          scope = changed.keys
          PallasTrade::Audit.record(
            action: action,
            actor: normalize_actor(actor),
            resource: product,
            before: before && before.slice(*scope),
            after: after.slice(*scope),
            metadata: metadata.merge('changed' => scope)
          )
        end

        # Records one bulk operation on every affected product, so each product
        # timeline shows the batch that touched it (with the batch counts).
        #
        # @param products [Enumerable<PallasTrade::Product>, ActiveRecord::Relation]
        def record_bulk(products:, action:, actor:, metadata: {})
          normalized = normalize_actor(actor)

          Array(products).each do |product|
            PallasTrade::Audit.record(
              action: action,
              actor: normalized,
              resource: product,
              metadata: metadata.compact.merge('source' => 'bulk')
            )
          end
        end

        private

        def update_action?(action)
          action.to_s == 'product.updated'
        end

        # @return [Hash] attribute => [before, after] for attributes that changed
        def changed_attributes(before, after)
          # A create has no prior state: every tracked attribute is "new".
          return after.transform_values { |value| [nil, value] } if before.blank?

          after.filter_map do |attribute, value|
            previous = before[attribute]
            [attribute, [previous, value]] unless previous == value
          end.to_h
        end

        # `Audit.record` stores AR actors without a label, so the timeline passes
        # a hash carrying a human-readable one.
        def normalize_actor(actor)
          return 'system' if actor.nil?
          return actor unless actor.respond_to?(:id) && actor.respond_to?(:class)

          { type: actor.class.name, id: actor.id, label: actor_label(actor) }
        end

        def actor_label(actor)
          %i[email name full_name].each do |method|
            value = actor.try(method)
            return value if value.present?
          end

          "##{actor.id}"
        end
      end
    end
  end
end
