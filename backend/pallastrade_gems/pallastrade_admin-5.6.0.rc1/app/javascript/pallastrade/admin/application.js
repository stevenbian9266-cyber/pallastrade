// Rails stuff
import "@rails/actioncable"
import "@rails/actiontext"
import "@hotwired/turbo-rails"
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

import "trix"

import "chartkick"
import "Chart.bundle"

import LocalTime from "local-time"
import "mapkick/bundle"

// Helpers
import 'pallastrade/admin/helpers/tinymce'
import 'pallastrade/admin/helpers/trix/video_embed'
import 'pallastrade/admin/helpers/turbo_confirm'

// Stimulus controllers
import { Application } from "@hotwired/stimulus"

let application
if (typeof Stimulus === 'undefined') {
  application = Application.start()

  // Configure Stimulus development experience
  application.debug = false
  window.Stimulus = application
} else {
  application = window.Stimulus
}
import AutoSubmit from '@stimulus-components/auto-submit'
import CheckboxSelectAll from 'stimulus-checkbox-select-all'
import Dialog from "@stimulus-components/dialog"
import TextareaAutogrow from 'stimulus-textarea-autogrow'
import Notification from 'stimulus-notification'
import PasswordVisibility from 'stimulus-password-visibility'
import RailsNestedForm from '@stimulus-components/rails-nested-form'
import Reveal from 'stimulus-reveal-controller'
import Sortable from 'stimulus-sortable'
import ActiveStorageUpload from 'pallastrade/admin/controllers/active_storage_upload_controller'
import AdminController from 'pallastrade/admin/controllers/admin_controller'
import AssetUploaderController from 'pallastrade/admin/controllers/asset_uploader_controller'
import AutocompleteSelectController from 'pallastrade/admin/controllers/autocomplete_select_controller'
import AutoScrollController from 'pallastrade/admin/controllers/auto_scroll_controller'
import BetterSliderController from 'pallastrade/admin/controllers/better_slider_controller'
import BlockFormController from 'pallastrade/admin/controllers/block_form_controller'
import BulkOperationController from 'pallastrade/admin/controllers/bulk_operation_controller'
import CalculatorFieldsController from 'pallastrade/admin/controllers/calculator_fields_controller'
import CalendarRangeController from 'pallastrade/admin/controllers/calendar_range_controller'
import Clipboard from 'pallastrade/admin/controllers/clipboard_controller'
import CodeMirrorController from 'pallastrade/admin/controllers/codemirror_controller'
import ColorPaletteController from 'pallastrade/admin/controllers/color_palette_controller'
import ColumnSelectorController from 'pallastrade/admin/controllers/column_selector_controller'
import ColorPickerController from 'pallastrade/admin/controllers/color_picker_controller'
import DisplayNameController from 'pallastrade/admin/controllers/display_name_controller'
import DropdownController from 'pallastrade/admin/controllers/dropdown_controller'
import FiltersController from 'pallastrade/admin/controllers/filters_controller'
import FontPickerController from 'pallastrade/admin/controllers/font_picker_controller'
import HighlightController from 'pallastrade/admin/controllers/highlight_controller'
import ImportFormController from 'pallastrade/admin/controllers/import_form_controller'
import MediaFormController from 'pallastrade/admin/controllers/media_form_controller'
import MoneyFieldController from 'pallastrade/admin/controllers/money_field_controller'
import MultiInputController from 'pallastrade/admin/controllers/multi_input_controller'
import MultiTomSelectController from 'pallastrade/admin/controllers/multi_tom_select_controller'
import OrderBillingAddressController from 'pallastrade/admin/controllers/order_billing_address_controller'
import PageBuilderController from 'pallastrade/admin/controllers/page_builder_controller'
import PasswordToggle from 'pallastrade/admin/controllers/password_toggle_controller'
import ProductFormController from 'pallastrade/admin/controllers/product_form_controller'
import ProductPublishingController from 'pallastrade/admin/controllers/product_publishing_controller'
import QueryBuilderController from 'pallastrade/admin/controllers/query_builder_controller'
import RangeInputController from 'pallastrade/admin/controllers/range_input_controller'
import TableController from 'pallastrade/admin/controllers/table_controller'
import ReturnItemsController from 'pallastrade/admin/controllers/return_items_controller'
import ReplaceController from 'pallastrade/admin/controllers/replace_controller'
import RowLinkController from 'pallastrade/admin/controllers/row_link_controller'
import RuleFormController from 'pallastrade/admin/controllers/rule_form_controller'
import SearchClearController from 'pallastrade/admin/controllers/search_clear_controller'
import SearchPickerController from 'pallastrade/admin/controllers/search_picker_controller'
import SectionFormController from 'pallastrade/admin/controllers/section_form_controller'
import SelectController from 'pallastrade/admin/controllers/select_controller'
import SeoFormController from 'pallastrade/admin/controllers/seo_form_controller'
import SidebarController from 'pallastrade/admin/controllers/sidebar_controller'
import SlugFormController from 'pallastrade/admin/controllers/slug_form_controller'
import StickyController from 'pallastrade/admin/controllers/sticky_controller'
import SortableAutoSubmit from 'pallastrade/admin/controllers/sortable_auto_submit_controller'
import SortableTree from 'pallastrade/admin/controllers/sortable_tree_controller'
import StockTransferController from 'pallastrade/admin/controllers/stock_transfer_controller'
import StoreFormController from 'pallastrade/admin/controllers/store_form_controller'
import TabsController from 'pallastrade/admin/controllers/tabs_controller'
import TooltipController from 'pallastrade/admin/controllers/tooltip_controller'
import TurboSubmitButtonController from 'pallastrade/admin/controllers/turbo_submit_button_controller'
import UnitSystemController from 'pallastrade/admin/controllers/unit_system_controller'
import VariantsFormController from 'pallastrade/admin/controllers/variants_form_controller'
import ZoneStateSelectController from 'pallastrade/admin/controllers/zone_state_select_controller'
import BulkEditorController from 'pallastrade/admin/controllers/bulk_editor_controller'
import AddressAutocompleteController from 'pallastrade/core/controllers/address_autocomplete_controller'
import AddressFormController from 'pallastrade/core/controllers/address_form_controller'
import DisableSubmitButtonController from 'pallastrade/core/controllers/disable_submit_button_controller'
import EnableButtonController from 'pallastrade/core/controllers/enable_button_controller'

application.register('active-storage-upload', ActiveStorageUpload)
application.register('address-autocomplete', AddressAutocompleteController)
application.register('address-form', AddressFormController)
application.register('admin', AdminController)
application.register('asset-uploader', AssetUploaderController)
application.register('auto-scroll', AutoScrollController)
application.register('auto-submit', AutoSubmit)
application.register('autocomplete-select', AutocompleteSelectController)
application.register('better-slider', BetterSliderController)
application.register('block-form', BlockFormController)
application.register('bulk-dialog', Dialog)
application.register('bulk-operation', BulkOperationController)
application.register('calculator-fields', CalculatorFieldsController)
application.register('calendar-range', CalendarRangeController)
application.register('checkbox-select-all', CheckboxSelectAll)
application.register('clipboard', Clipboard)
application.register('codemirror', CodeMirrorController)
application.register('color-palette', ColorPaletteController)
application.register('color-picker', ColorPickerController)
application.register('column-selector', ColumnSelectorController)
application.register('display-name', DisplayNameController)
application.register('dialog', Dialog)
application.register('drawer', Dialog)
application.register('disable-submit-button', DisableSubmitButtonController)
application.register('dropdown', DropdownController)
application.register('enable-button', EnableButtonController)
application.register('export-dialog', Dialog)
application.register('filters', FiltersController)
application.register('font-picker', FontPickerController)
application.register('highlight', HighlightController)
application.register('import-form', ImportFormController)
application.register('media-form', MediaFormController)
application.register('money-field', MoneyFieldController)
application.register('multi-input', MultiInputController)
application.register('multi-tom-select', MultiTomSelectController)
application.register('nested-form', RailsNestedForm)
application.register('notification', Notification)
application.register('order-billing-address', OrderBillingAddressController)
application.register('page-builder', PageBuilderController)
application.register('password-toggle', PasswordToggle)
application.register('password-visibility', PasswordVisibility)
application.register('product-form', ProductFormController)
application.register('product-publishing', ProductPublishingController)
application.register('query-builder', QueryBuilderController)
application.register('range-input', RangeInputController)
application.register('table', TableController)
application.register('replace', ReplaceController)
application.register('return-items', ReturnItemsController)
application.register('reveal', Reveal)
application.register('row-link', RowLinkController)
application.register('rule-form', RuleFormController)
application.register('search-clear', SearchClearController)
application.register('search-picker', SearchPickerController)
application.register('section-form', SectionFormController)
application.register('select', SelectController)
application.register('seo-form', SeoFormController)
application.register('sidebar', SidebarController)
application.register('slug-form', SlugFormController)
application.register('sticky', StickyController)
application.register('sortable', Sortable)
application.register('sortable-auto-submit', SortableAutoSubmit)
application.register('sortable-tree', SortableTree)
application.register('stock-transfer', StockTransferController)
application.register('store-form', StoreFormController)
application.register('tabs', TabsController)
application.register('tooltip', TooltipController)
application.register('turbo-submit-button', TurboSubmitButtonController)
application.register('textarea-autogrow', TextareaAutogrow)
application.register('unit-system', UnitSystemController)
application.register('variants-form', VariantsFormController)
application.register('zone-state-select', ZoneStateSelectController)
application.register('bulk-editor', BulkEditorController)

LocalTime.start()

Trix.config.blockAttributes.heading1.tagName = 'h2'

document.addEventListener('turbo:before-visit', _event => {
  const content = document.getElementById('content')
  if (content) content.classList.add('blurred')
})

document.addEventListener('turbo:load', _event => {
  const content = document.getElementById('content')
  if (content) content.classList.remove('blurred')
})

document.addEventListener('turbo:submit-start', () => {
  Turbo.navigator.delegate.adapter.progressBar.setValue(0)
  Turbo.navigator.delegate.adapter.progressBar.show()
})
document.addEventListener('turbo:submit-end', () => {
  Turbo.navigator.delegate.adapter.progressBar.setValue(1)
  Turbo.navigator.delegate.adapter.progressBar.hide()
})
