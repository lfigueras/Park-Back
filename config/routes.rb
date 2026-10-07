Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  root "parking_locations#index"

  get "privacy", to: "privacy#show"
  patch "privacy/preferences", to: "privacy#update", as: :privacy_preferences
  get "privacy/data", to: "privacy#export", as: :privacy_data
  delete "privacy/data", to: "privacy#destroy"

  resources :parking_locations, only: %i[new create show destroy] do
    get :photo, on: :member
  end

  namespace :admin do
    resources :photos, only: %i[index show]
  end
end
