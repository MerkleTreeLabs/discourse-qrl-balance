# frozen_string_literal: true

# name: discourse-qrl-address-balance
# about: Displays QRL address balance from the QRL Explorer API on Discourse topic pages.
# version: 0.1.0
# authors: Your Name/AI
# url: https://github.com/your-username/discourse-qrl-address-balance

# General asset registration (like CSS/JS) can be placed outside `after_initialize`
# as the plugin loader processes these separately during its initial pass.
register_asset 'stylesheets/common/qrl-address-balance.scss'


# The `after_initialize` block is crucial. All methods that interact with Discourse's
# plugin API (like adding site settings, routes, custom fields, serializers,
# or defining new classes like controllers) MUST be called within this block.
after_initialize do
  # --- Define new site settings for the plugin ---
  # These will appear in Admin -> Settings -> Plugins for easy configuration.
  # These calls are now correctly placed inside `after_initialize`.
  add_admin_option(:general, {
    setting: :qrl_address_balance_enabled,
    type: :boolean,
    default: true,
    description: "Enable the QRL Address Balance plugin."
  })
  add_admin_option(:general, {
    setting: :qrl_explorer_base_url,
    type: :string,
    default: "https://explorer.theqrl.org",
    description: "Enter the base URL for the QRL Explorer API. E.g., https://explorer.theqrl.org"
  })
  add_admin_option(:general, {
    setting: :qrl_category_id,
    type: :category_id,
    description: "Select the Discourse category where QRL address balances should display."
  })
  add_admin_option(:general, {
    setting: :qrl_balance_refresh_interval_minutes,
    type: :integer,
    default: 5,
    min: 1,
    description: "How often to refresh the QRL balance data on the client side (in minutes)."
  })

  # --- Define a custom route for our server-side proxy ---
  # This route acts as an intermediary, fetching data from the QRL Explorer API.
  # This block is also correctly placed inside `after_initialize`.
  Discourse::Application.routes.append do
    get '/qrl-proxy/balance/:address' => 'qrl_proxy#show', constraints: { address: /.*/, format: false }
  end

  # --- Conditional Execution based on Plugin Enablement ---
  # It's good practice to wrap the core logic that requires the plugin to be active.
  # This ensures resources aren't consumed needlessly if the plugin is disabled via settings.
  return unless SiteSetting.qrl_address_balance_enabled

  # --- Register a custom topic field ---
  # This allows us to store the QRL address directly on Discourse topics.
  # Correctly placed inside `after_initialize`.
  Discourse::Topic.register_custom_field_type('qrl_address', :string)
  Discourse::Topic.track_topic_custom_fields(['qrl_address'])

  # --- Add custom fields to JSON serializers ---
  # These modifications make the `qrl_address` available to the client-side JavaScript,
  # embedded directly within the topic's data when it's loaded.
  # Correctly placed inside `after_initialize`.
  add_to_serializer(:topic_view, :qrl_address) do
    object.topic.custom_fields['qrl_address']
  end

  add_to_serializer(:topic_list_item, :qrl_address) do
    object.custom_fields['qrl_address']
  end

  # --- Define our custom QRL Proxy Controller ---
  # This controller handles the server-side logic for fetching QRL balances.
  # It must be defined inside `after_initialize` for proper loading.
  class DiscourseQrlAddressBalance::QrlProxyController < ApplicationController
    requires_plugin 'discourse-qrl-address-balance' # Ensures this controller is tied to our plugin
    # These skips are vital for a proxy. They prevent Discourse's default behavior
    # that expects typical internal XHR requests.
    skip_before_action :check_xhr, :preload_json

    def show
      address = params[:address]

      # --- QRL Address Validation ---
      # Basic regex to check for a QRL address format: starts with 'Q' followed by 78 hex characters.
      unless address.present? && address =~ /^Q[0-9a-fA-F]{78}$/
        return render json: { success: false, error: 'Invalid QRL address format provided.' }, status: :bad_request
      end

      # Retrieve the base URL for the QRL Explorer API from site settings.
      qrl_explorer_base_url = SiteSetting.qrl_explorer_base_url
      if qrl_explorer_base_url.blank?
        return render json: { success: false, error: 'QRL Explorer base URL is not configured in site settings.' }, status: :internal_server_error
      end

      # Construct the full API URL based on the specified base URL and the address.
      # Example format: https://explorer.theqrl.org/api/a/{address}
      qrl_api_url = "#{qrl_explorer_base_url}/api/a/#{address}"

      begin
        uri = URI(qrl_api_url)
        # Use Ruby's built-in Net::HTTP to make a GET request to the external API.
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess) # Check if the external API call was successful (HTTP 2xx status)
          data = JSON.parse(response.body) # Parse the JSON response from the QRL Explorer.

          # Extract the 'balance' value from the nested JSON structure.
          # The provided QRL Explorer API response has the balance under `state.balance`.
          raw_balance_str = data.dig("state", "balance")

          if raw_balance_str.present?
            # --- QRL Unit Conversion ---
            # QRL balances from the API are in the smallest unit (quanta).
            # 1 QRL = 1,000,000,000 (10^9) quanta.
            # We use BigDecimal for precise floating-point division to avoid errors.
            balance_big_decimal = BigDecimal(raw_balance_str) / BigDecimal("1000000000")
            # Format the balance to 9 decimal places for consistency and readability.
            formatted_balance = '%.9f' % balance_big_decimal.truncate(9)

            # Return a successful JSON response to the client.
            render json: { success: true, qrl_address: address, balance: formatted_balance.to_s }
          else
            # If `balance` key is not found where expected in the API response.
            render json: { success: false, error: 'Balance data not found in QRL API response.', api_response: data }, status: :internal_server_error
          end
        else
          # If the external API call returns an error (e.g., 404 Not Found, 500 Server Error).
          # We forward the external API's status code and a descriptive error message.
          render json: { success: false, error: "Failed to fetch balance from QRL Explorer: #{response.code} - #{response.message}", external_status: response.code }, status: response.code
        end
      rescue JSON::ParserError => e
        # Handle cases where the external API returns malformed or invalid JSON.
        render json: { success: false, error: "Invalid JSON response from QRL Explorer API: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        # Catch any other unexpected exceptions during the API call (e.g., network issues).
        render json: { success: false, error: "An unexpected error occurred while contacting QRL Explorer API: #{e.message}" }, status: :internal_server_error
      end
    end
  end
end