# Keep unmatched API routes on the JSON error contract. Without this fallback,
# Rails renders its HTML routing-error page in development and test.
Rails.application.routes.append do
  match 'api/*unmatched', to: 'api_errors#not_found', via: :all, defaults: { format: :json }
end
