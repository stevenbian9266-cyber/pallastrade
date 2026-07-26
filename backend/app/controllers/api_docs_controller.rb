# frozen_string_literal: true

# Serves API documentation using Scalar UI.
# OpenAPI YAML specs are served as static files from public/api-docs/.
class ApiDocsController < ApplicationController
  # GET /docs/api
  # Landing page — choose between Store API and Admin API documentation.
  def index; end

  # GET /docs/api/store
  def store
    @title = 'Store API'
    @spec_url = '/api-docs/store.yaml'
    render :swagger
  end

  # GET /docs/api/admin
  def admin
    @title = 'Admin API'
    @spec_url = '/api-docs/admin.yaml'
    render :swagger
  end
end
