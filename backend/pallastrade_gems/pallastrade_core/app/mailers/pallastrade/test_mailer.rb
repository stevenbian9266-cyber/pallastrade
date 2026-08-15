# frozen_string_literal: true

module PallasTrade
  # Used by the Email → Templates "test send" action to deliver the rendered
  # DB template (subject + HTML + text) through the normal store mail path.
  class TestMailer < BaseMailer
    def test_email(to:, subject:, body_html:, body_text:, store: nil)
      @store = store
      @body_html = body_html.to_s.html_safe
      @body_text = body_text.to_s
      @subject = subject

      mail(to: to, subject: subject, store_url: store&.storefront_url)
    end
  end
end
