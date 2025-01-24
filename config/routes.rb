require "sidekiq/web"

Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  resources :accounts, only: [ :create ] do
    resources :account_users, only: %i[create index destroy], module: :accounts
    member do
      get :switch
    end
  end
  namespace :inbound_webhooks do
    resources :github, controller: :github, only: [ :create ]
  end
  get "/privacy", to: "static#privacy"
  get "/terms", to: "static#terms"
  get "/manifesto", to: "static#manifesto"

  authenticated :user do
    root to: "projects#index", as: :user_root
    # Alternate route to use if logged in users should still see public root
    # get "/dashboard", to: "dashboard#show", as: :user_root
  end
  get "/integrations/github/repositories", to: "integrations/github/repositories#index"
  resources :add_ons do
    collection do
      get :search
      get :default_values
    end
    member do
      post :restart
    end
    resources :endpoints, only: %i[edit update], module: :add_ons
    resources :processes, only: %i[index show], module: :add_ons
  end

  resources :projects do
    member do
      post :restart
    end
    collection do
      get "/:project_id/deployments", to: "projects/deployments#index", as: :root
    end
    resources :volumes, only: %i[index new create destroy], module: :projects
    resources :processes, only: %i[index show create destroy], module: :projects
    resources :services, only: %i[index new create destroy update], module: :projects do
      resources :jobs, only: %i[create], module: :services
      resources :domains, only: %i[create destroy], module: :services do
        collection do
          post :check_dns
        end
      end
    end
    resources :metrics, only: [ :index ], module: :projects
    resources :project_add_ons, only: %i[create destroy], module: :projects
    resources :environment_variables, only: %i[index create destroy], module: :projects
    resources :deployments, only: %i[index show], module: :projects do
      collection do
        post :deploy
      end
      member do
        post :redeploy
      end
    end
  end
  resources :clusters do
    member do
      get :download_kubeconfig
      get :download_yaml
      get :logs
    end
    resource :metrics, only: [ :show ], module: :clusters
    member do
      post :test_connection
      post :retry_install
    end
    collection do
      post :check_k3s_ip_address
    end
  end

  authenticate :user, lambda { |u| u.admin? } do
    namespace :admin do
      mount Sidekiq::Web => "/sidekiq"
    end
  end

  resources :notifications, only: [ :index ]
  resources :announcements, only: [ :index ]
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks", registrations: "users/registrations", sessions: "users/sessions" }
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "async_render" => "async_renderer#async_render"

  # Public marketing homepage
  if Rails.application.config.local_mode
    get "/github_token", to: "local/pages#github_token"
    put "/github_token", to: "local/pages#update_github_token"
    root to: "projects#index"
  else
    root to: "static#index"
  end
end
