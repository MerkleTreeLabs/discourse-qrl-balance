# frozen_string_literal: true

# name: discourse-qrl-balance
# about: Displays QRL address balance from the QRL Explorer API on Discourse topic pages.
# version: 0.1.0
# authors: Your Name/AI
# url: https://github.com/your-username/discourse-qrl-balance

# General asset registration (stays at the top level)
register_asset 'stylesheets/common/qrl-address-balance.scss'


# The `after_initialize` block contains all other plugin logic.
after_initialize do
  # --- Define a custom route for our server-side proxy ---
  # This route acts as an intermediary, fetching data from the QRL Explorer API.
  # This section does NOT depend on SiteSetting.qrl_address_balance_enabled,
  # so it can stay near the top of after_initialize.
  Discourse::Application.routes.append do
    get '/qrl-proxy/balance/:address' => 'qrl_proxy#show', constraints: { address: /.*/, format: false }
  end

  # --- Register a custom topic field ---
  # This also does NOT depend on SiteSetting.qrl_address_balance_enabled.
  Discourse::Topic.register_custom_field_type('qrl_address', :string)
  Discourse::Topic.track_topic_custom_fields(['qrl_address'])

  # --- Add custom fields to JSON serializers ---
  # These also DO NOT depend on SiteSetting.qrl_address_balance_enabled.
  add_to_serializer(:topic_view, :qrl_address) do
    object.topic.custom_fields['qrl_address']
  end

  add_to_serializer(:topic_list_item, :qrl_address) do
    object.custom_fields['qrl_address']
  end

  # --- Conditional Execution based on Plugin Enablement ---
  # THIS IS THE CRITICAL CHANGE: Move this line DOWN!
  # It must come *after* the settings have been fully loaded and registered.
  # If the plugin is disabled, the rest of the code in THIS block (i.e., the controller definition)
  # will not execute, but the routes, custom fields, and serializers will still be set up (which is fine).
  return unless SiteSetting.qrl_address_balance_enabled

  # --- Define our custom QRL Proxy Controller ---
  # This whole class definition and its logic *depends* on the plugin being enabled.
  # Therefore, it should be placed *after* the `return unless` check.
  class DiscourseQrlAddressBalance::QrlProxyController < ApplicationController
    requires_plugin 'discourse-qrl-balance' # Ensures this controller is tied to our plugin
    skip_before_action :check_xhr, :preload_json

    def show
      address = params[:address]

      unless address.present? && address =~ /^Q[0-9a-fA-F]{78}$/
        return render json: { success: false, error: 'Invalid QRL address format provided.' }, status: :bad_request
      end

      # SiteSetting.qrl_explorer_base_url is also used here, and this code is now
      # correctly placed *after* the main enable check.
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