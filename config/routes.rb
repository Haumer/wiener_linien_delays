Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  get "delays", to: "pages#delays"
  get "delays/:line", to: "pages#line_delays", as: :line_delays
  # get "network", to: "pages#network"
  # get "fleet", to: "pages#fleet"

  namespace :api do
    get :vehicles, to: "vehicles#index"
    get :stops, to: "stops#index"
    get "stops/departures", to: "stops#departures", as: :stops_departures
    get :lines, to: "lines#index"
    get :line_health, to: "line_health#index"
    get "line_health/history", to: "line_health#history"
    get :disruptions, to: "disruptions#index"
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
