Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  get "delays", to: "pages#delays"
  get "delays/:line", to: "pages#line_delays", as: :line_delays

  namespace :api do
    get :cities, to: "cities#index"
    get :vehicles, to: "vehicles#index"
    # Map demo stubs
    get :stops, to: "stubs#empty_array"
    get "stops/departures", to: "stubs#empty_array", as: :stops_departures
    get :lines, to: "stubs#empty_geojson"
    get :line_health, to: "line_health#index"
    get "line_health/history", to: "line_health#history"
    get :disruptions, to: "disruptions#index"
    get :stop_delays, to: "stop_delays#index"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
