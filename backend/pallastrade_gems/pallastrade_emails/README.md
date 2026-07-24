# PallasTrade Emails

[![Gem Version](https://badge.fury.io/rb/pallastrade_emails.svg)](https://badge.fury.io/rb/pallastrade_emails)

PallasTrade Emails provides transactional email templates and mailers for PallasTrade Commerce, handling order confirmations, shipment notifications, and other customer communications.

## Overview

This gem includes:

- **Order Mailer** - Order confirmation and cancellation emails
- **Shipment Mailer** - Shipping and delivery notifications
- **Reimbursement Mailer** - Refund notifications
- **Event Subscribers** - Automatic email triggers on store events
- **Email Templates** - Customizable HTML and text templates

## Installation

```bash
bundle add pallastrade_emails
```

## Email Types

### Order Emails

- **Order Confirmation** - Sent when an order is completed
- **Order Cancellation** - Sent when an order is cancelled

### Shipment Emails

- **Shipment Notification** - Sent when a shipment is shipped
- **Delivery Confirmation** - Sent when tracking shows delivered

### Reimbursement Emails

- **Refund Notification** - Sent when a reimbursement is processed

## Configuration

Transactional emails are controlled per-store via the `send_consumer_transactional_emails` preference. This can be configured in the admin dashboard under Store Settings, or programmatically:

```ruby
# Enable/disable transactional emails for a store
store = PallasTrade::Store.current
store.update(send_consumer_transactional_emails: true)
```

The sender address is configured via the `mail_from_address` attribute on each store:

```ruby
store.update(mail_from_address: 'orders@example.com')
```

### Action Mailer Configuration

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: 'smtp.example.com',
  port: 587,
  user_name: ENV['SMTP_USERNAME'],
  password: ENV['SMTP_PASSWORD'],
  authentication: 'plain',
  enable_starttls_auto: true
}
```

## Customization

### Overriding Templates

Copy email templates to your application:

```bash
# Copy all email templates
cp -r $(bundle show pallastrade_emails)/app/views/pallastrade/mailer app/views/pallastrade/

# Or copy specific templates
cp $(bundle show pallastrade_emails)/app/views/pallastrade/mailer/order_mailer/confirm_email.html.erb \
   app/views/pallastrade/mailer/order_mailer/
```

### Template Structure

```
app/views/pallastrade/mailer/
├── order_mailer/
│   ├── confirm_email.html.erb
│   ├── confirm_email.text.erb
│   ├── cancel_email.html.erb
│   └── cancel_email.text.erb
├── shipment_mailer/
│   ├── shipped_email.html.erb
│   └── shipped_email.text.erb
└── reimbursement_mailer/
    ├── reimbursement_email.html.erb
    └── reimbursement_email.text.erb
```

### Custom Mailer

Create custom mailers by extending PallasTrade's base mailer:

```ruby
# app/mailers/pallastrade/order_mailer_decorator.rb
module PallasTrade
  module OrderMailerDecorator
    def confirm_email(order, resend = false)
      @custom_data = fetch_custom_data(order)
      super
    end

    private

    def fetch_custom_data(order)
      # Custom logic
    end
  end
end

PallasTrade::OrderMailer.prepend(PallasTrade::OrderMailerDecorator)
```

### Adding New Email Types

```ruby
# app/mailers/pallastrade/custom_mailer.rb
module PallasTrade
  class CustomMailer < BaseMailer
    def welcome_email(user)
      @user = user
      mail(to: @user.email, subject: 'Welcome to our store!')
    end
  end
end
```

## Event Integration

Emails are triggered via PallasTrade's event system. Create custom subscribers:

```ruby
# app/subscribers/my_app/custom_email_subscriber.rb
module MyApp
  class CustomEmailSubscriber < PallasTrade::Subscriber
    subscribes_to 'customer.created'

    def handle(event)
      user_id = event.payload['id']
      user = PallasTrade.user_class.find_by(id: user_id)
      return unless user

      PallasTrade::CustomMailer.welcome_email(user).deliver_later
    end
  end
end
```

Then register the subscriber in an initializer:

```ruby
# config/initializers/pallastrade.rb
Rails.application.config.after_initialize do
  PallasTrade.subscribers << MyApp::CustomEmailSubscriber
end
```

## Disabling Emails

Disable transactional emails for a specific store:

```ruby
store = PallasTrade::Store.current
store.update(send_consumer_transactional_emails: false)
```

This setting can also be managed in the admin dashboard under Store Settings.

To disable all PallasTrade transactional emails globally, remove this gem from your application:

```bash
bundle remove pallastrade_emails
```

### Using Third-Party Email Services

If you prefer to use a third-party email service like Klaviyo for transactional emails, you can use the [pallastrade_klaviyo](https://github.com/stevenbian9266-cyber/pallastrade) extension. This allows you to leverage Klaviyo's email marketing platform for order confirmations, shipment notifications, and other transactional emails.

## Previewing emails

[ActionMailer previews](https://guides.rubyonrails.org/action_mailer_basics.html#previewing-and-testing-mailers) for every transactional email ship with this gem and are served automatically in development — no setup required. With a seeded development database, start the server and visit:

`http://localhost:3000/rails/mailers`

for example `http://localhost:3000/rails/mailers/pallastrade/order/confirm_email`.

## Testing

Run the test suite:

```bash
cd emails
bundle exec rake test_app  # First time only
bundle exec rspec
```

## Documentation

- [Email Customization Guide](https://pallastrade.cn/docs/developer/customization/emails)
- [Events System](https://pallastrade.cn/docs/developer/core-concepts/events)