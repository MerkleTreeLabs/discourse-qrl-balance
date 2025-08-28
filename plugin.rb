# frozen_string_literal: true

# name: discourse-qrl-address-balance
# about: Displays QRL address balance from the QRL Explorer API on Discourse topic pages.
# version: 0.1.0
# authors: Your Name/AI
# url: https://github.com/your-username/discourse-qrl-address-balance

# General asset registration
register_asset 'stylesheets/common/qrl-address-balance.scss'

# --- NEW APPROACH FOR ADDING SITE SETTINGS ---
# Define plugin settings using DiscoursePluginRegistry.
# This is a robust way to add settings and is often used by core plugins.
# These calls are placed directly at the top level of plugin.rb.
DiscoursePluginRegistry.add_plugin_setting(:qrl_address_balance_enabled, {
  default: true,
  type: :boolean,
  description: "Enable the QRL Address Balance plugin."
})
DiscoursePluginRegistry.add_plugin_setting(:qrl_explorer_base_url, {
  default: "https://explorer.theqrl.org",
  type: :string,
  description: "Enter the base URL for the QRL Explorer API. E.g., https://explorer.theqrl.org"
})
DiscoursePluginRegistry.add_plugin_setting(:qrl_category_id, {
  type: :category_id,
  description: "Select the Discourse category where QRL address balances should display."
})
DiscoursePluginRegistry.add_plugin_setting(:qrl_balance_refresh_interval_minutes, {
  default: 5,
  type: :integer,
  min: 1,
  description: "How often to refresh the QRL balance data on the client side (in minutes)."
})

# The `after_initialize` block contains all other plugin logic.
after_initialize do
  # --- Define a custom route for our server-side proxy ---
  # This route acts as an intermediary, fetching data from the QRL Explorer API.
  Discourse::Application.routes.append do
    get '/qrl-proxy/balance/:address' => 'qrl_proxy#show', constraints: { address: /.*/, format: false }
  end

  # --- Conditional Execution based on Plugin Enablement ---
  return unless SiteSetting.qrl_address_balance_enabled

  # --- Register a custom topic field ---
  Discourse::Topic.register_custom_field_type('qrl_address', :string)
  Discourse::Topic.track_topic_custom_fields(['qrl_address'])

  # --- Add custom fields to JSON serializers ---
  add_to_serializer(:topic_view, :qrl_address) do
    object.topic.custom_fields['qrl_address']
  end

  add_to_serializer(:topic_list_item, :qrl_address) do
    object.custom_fields['qrl_address']
  end

  # --- Define our custom QRL Proxy Controller ---
  class DiscourseQrlAddressBalance::QrlProxyController < ApplicationController
    requires_plugin 'discourse-qrl-address-balance'
    skip_before_action :check_xhr, :preload_json

    def show
      address = params[:address]

      unless address.present? && address =~ /^Q[0-9a-fA-F]{78}$/
        return render json: { success: false, error: 'Invalid QRL address format provided.' }, status: :bad_request
      end

      qrl_explorer_base_url = SiteSetting.qrl_explorer_base_url
      if qrl_explorer_base_url.blank?
        return render json: { success: false, error: 'QRL Explorer base URL is not configured in site settings.' }, status: :internal_server_error
      end

      qrl_api_url = "#{qrl_explorer_base_url}/api/a/#{address}"

      begin
        uri = URI(qrl_api_url)
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          raw_balance_str = data.dig("state", "balance")

          if raw_balance_str.present?
            balance_big_decimal = BigDecimal(raw_balance_str) / BigDecimal("1000000000")
            formatted_balance = '%.9f' % balance_big_decimal.truncate(9)

            render json: { success: true, qrl_address: address, balance: formatted_balance.to_s }
          else
            render json: { success: false, error: 'Balance data not found in QRL API response.', api_response: data }, status: :internal_server_error
          end
        else
          render json: { success: false, error: "Failed to fetch balance from QRL Explorer: #{response.code} - #{response.message}", external_status: response.code }, status: response.code
        end
      rescue JSON::ParserError => e
        render json: { success: false, error: "Invalid JSON response from QRL Explorer API: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        render json: { success: false, error: "An unexpected error occurred while contacting QRL Explorer API: #{e.message}" }, status: :internal_server_error
      end
    end
  end
end