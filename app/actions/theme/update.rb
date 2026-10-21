# frozen_string_literal: true

module Tally
  module Actions
    module Theme
      # Switches this browser between the dark and light themes, or back to following the
      # system's ("system" forgets the choice), and goes back to the page it came from.
      class Update < Tally::Action
        def handle(request, response)
          if request.params[:theme] == Tally::Themes::SYSTEM
            response.cookies[Tally::Themes::COOKIE] = nil
          else
            theme = Tally::Themes.pick(request.params[:theme]) or halt 422
            remember(response, Tally::Themes::COOKIE, theme)
          end
          response.redirect_to(back_param(request.params[:back]) || "/")
        end
      end
    end
  end
end
