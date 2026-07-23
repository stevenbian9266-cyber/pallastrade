class ApiErrorsController < ActionController::API
  def not_found
    render json: {
      error: {
        code: 'route_not_found',
        message: 'API endpoint not found'
      }
    }, status: :not_found
  end
end
