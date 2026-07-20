require_relative 'preview_data'

# Preview Spree export emails at /rails/mailers/spree/export
class PallasTrade::ExportPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def export_done
    PallasTrade::ExportMailer.export_done(export)
  end

  private

  # Reuse the most recent export, or build an in-memory example so the preview
  # works on a database that has never run an export. When the preview toolbar
  # requests a locale, always use the example so its store carries that locale.
  # The example is never saved, so no `export.created` side effects fire.
  def export
    return example_export if locale.present?

    PallasTrade::Export.last || example_export
  end

  def example_export
    export = PallasTrade::Exports::Products.new(
      id: 0,
      store: PallasTrade::PreviewData.store(locale),
      user: PallasTrade::PreviewData.admin_user,
      format: :csv
    )
    export.attachment.attach(
      io: StringIO.new("id,name,price\n1,Example Product,19.99\n"),
      filename: 'products-export.csv',
      content_type: 'text/csv'
    )
    export
  end
end
