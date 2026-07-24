require 'cancan'
require_dependency 'pallastrade/core/controller_helpers/strong_parameters'

class PallasTrade::BaseController < ApplicationController
  include PallasTrade::Core::ControllerHelpers::Auth
  include PallasTrade::Core::ControllerHelpers::Store
  include PallasTrade::Core::ControllerHelpers::StrongParameters
  include PallasTrade::Core::ControllerHelpers::Locale
  include PallasTrade::Core::ControllerHelpers::Currency
  include PallasTrade::Core::ControllerHelpers::Turbo
end
