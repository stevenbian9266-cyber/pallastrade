# frozen_string_literal: true

module PallasTrade
  module Api
    module V3
      module Admin
        # Admin API for the Config Center ({PallasTrade::ConfigItem}).
        #
        # Auth: scoped to `read_settings` / `write_settings` (already granted to
        # settings-capable API keys) plus CanCanCan `manage` for JWT admins.
        class ConfigItemsController < ResourceController
          scoped_resource :settings

          # POST /api/v3/admin/config_items
          # `value` is routed to the correct lane by value_type (encrypted for
          # secret items). Blank `value` on an existing secret item leaves it
          # unchanged.
          def create
            @resource = build_resource
            authorize_resource!(@resource, :create)
            apply_value_param(@resource)

            if @resource.save
              render json: serialize_resource(@resource), status: :created
            else
              render_errors(@resource.errors)
            end
          end

          # PATCH /api/v3/admin/config_items/:id
          def update
            @resource = find_resource
            authorize_resource!(@resource, :update)
            @resource.assign_attributes(permitted_params)
            apply_value_param(@resource)

            if @resource.save
              render json: serialize_resource(@resource)
            else
              render_errors(@resource.errors)
            end
          end

          # POST /api/v3/admin/config_items/import
          # Bulk upsert used by the admin import wizard (e.g. importing known
          # .env parameters). Returns per-entry result.
          def import
            entries = Array(params[:items])
            results = entries.map do |entry|
              item = scope.find_or_initialize_by(key: entry[:key].to_s)
              item.group = entry[:group].to_s if entry[:group].present?
              item.value_type = entry[:value_type].to_s.presence || 'string'
              item.description = entry[:description].to_s if entry[:description].present?
              item.default_value = entry[:default_value].to_s if entry[:default_value].present?
              item.assign_value(entry[:value]) if entry.key?(:value) && !entry[:value].nil?
              {
                key: item.key,
                saved: item.save,
                errors: item.errors.full_messages
              }
            end

            render json: { data: results }
          end

          protected

          def model_class
            PallasTrade::ConfigItem
          end

          def serializer_class
            PallasTrade.api.admin_config_item_serializer
          end

          def scope
            current_store.config_items.accessible_by(current_ability, :show)
          end

          # `key` and `value_type` are create-only; updates are limited to the
          # human-facing attributes (value is handled via apply_value_param).
          def permitted_params
            if action_name == 'update'
              params.permit(:group, :description, :default_value)
            else
              params.permit(:key, :group, :value_type, :description, :default_value)
            end
          end

          private

          # Routes `value` to the correct storage lane. A blank value on an
          # existing secret item means "leave unchanged" (edit form sends no
          # value when the field is left empty).
          def apply_value_param(item)
            return unless params.key?(:value)
            return if params[:value].nil?
            return if params[:value].blank? && item.secret? && item.persisted?

            item.assign_value(params[:value])
          end
        end
      end
    end
  end
end
