require_relative 'preview_data'

# Preview Spree report emails at /rails/mailers/pallastrade/report
class PallasTrade::ReportPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def report_done
    PallasTrade::ReportMailer.report_done(report)
  end

  private

  # Reuse the most recent report, or build an in-memory example so the preview
  # works on a database that has never run a report. When the preview toolbar
  # requests a locale, always use the example so its store carries that locale.
  # The example is never saved, so no `report.created` side effects fire.
  def report
    return example_report if locale.present?

    PallasTrade::Report.last || example_report
  end

  def example_report
    store = PallasTrade::PreviewData.store(locale)
    report = PallasTrade::Reports::SalesTotal.new(
      id: 0,
      store: store,
      user: PallasTrade::PreviewData.admin_user,
      date_from: 30.days.ago.to_date,
      date_to: Date.current,
      currency: store.default_currency
    )
    report.attachment.attach(
      io: StringIO.new("date,total\n2026-01-01,1234.56\n"),
      filename: 'sales-total.csv',
      content_type: 'text/csv'
    )
    report
  end
end
