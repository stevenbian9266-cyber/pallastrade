module PallasTrade
  module Admin
    class ImportRowsController < ResourceController
      belongs_to 'pallastrade/import', find_by: :prefix_id
    end
  end
end
