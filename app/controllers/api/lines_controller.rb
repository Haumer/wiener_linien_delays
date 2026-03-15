module Api
  class LinesController < ApplicationController
    skip_before_action :authenticate_user!

    def index
      render json: LineOverlayService.new.call
    end
  end
end
