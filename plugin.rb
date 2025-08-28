# frozen_string_literal: true

# name: Discourse-QRL-Balance
# about: Displays QRL address balance from the QRL Explorer API on Discourse topic pages.
# version: 0.1.0
# authors: Fr1t2/AI
# url: https://github.com/MerkleTreeLabs/Discourse-QRL-Balance

# Define new site settings for the plugin
# These will appear in Admin -> Settings -> Plugins
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

# Register plugin assets
# These files will be compiled and served by Discourse
register_asset 'stylesheets/common/qrl-address-balance.scss'

# Define a custom route for our server-side proxy
# This route will fetch data from the QRL Explorer API and return it to the client
Discourse::Application.routes.append do
  get '/qrl-proxy/balance/:address' => 'qrl_proxy#show', constraints: { address: /.*/, format: false }
end

after_initialize do
  # Ensure the plugin is enabled before proceeding
  # This makes sure our code only runs if the admin has enabled the plugin
  return unless SiteSetting.qrl_address_balance_enabled

  # Register a custom topic field to store the QRL address
  # This field can be set by an administrator when creating or editing a topic
  Discourse::Topic.register_custom_field_type('qrl_address', :string)
  Discourse::Topic.track_topic_custom_fields(['qrl_address'])

  # Add the 'qrl_address' custom field to the JSON serialization for topic_view
  # This makes the qrl_address accessible in client-side Ember models for individual topics
  add_to_serializer(:topic_view, :qrl_address) do
    object.topic.custom_fields['qrl_address']
  end

  # Add the 'qrl_address' custom field to the JSON serialization for topic_list_item
  # This makes the qrl_address accessible in client-side Ember models for topics in a list
  add_to_serializer(:topic_list_item, :qrl_address) do
    object.custom_fields['qrl_address']
  end

  # Define our QRL Proxy Controller
  # This controller acts as an intermediary between the client and the QRL Explorer API
  class DiscourseQrlAddressBalance::QrlProxyController < ApplicationController
    requires_plugin 'discourse-qrl-address-balance' # Ensure the plugin is active
    # Skip checks that are typically for Discourse's own internal API calls
    # This allows it to function as a direct proxy for external services
    skip_before_action :check_xhr, :preload_json

    def show
      address = params[:address]

      # Basic validation for QRL address format
      # QRL addresses typically start with 'Q' and are exactly 79 characters long (Q + 78 hex chars).
      unless address.present? && address =~ /^Q[0-9a-fA-F]{78}$/
        return render json: { success: false, error: 'Invalid QRL address format provided.' }, status: :bad_request
      end

      qrl_explorer_base_url = SiteSetting.qrl_explorer_base_url
      if qrl_explorer_base_url.blank?
        return render json: { success: false, error: 'QRL Explorer base URL is not configured in site settings.' }, status: :internal_server_error
      end

      # Construct the full API URL based on the provided example QRL Explorer API structure
      # Example: https://explorer.theqrl.org/api/a/{address}
      qrl_api_url = "#{qrl_explorer_base_url}/api/a/#{address}"

      begin
        uri = URI(qrl_api_url)
        # Use Net::HTTP for simple HTTP GET requests to the external API
        response = Net::HTTP.get_response(uri)

        if response.is_a?(Net::HTTPSuccess) # Check if the HTTP request was successful (2xx status code)
          data = JSON.parse(response.body)

          # Extract the 'balance' from the nested JSON structure
          # The balance is expected to be under `state.balance`
          # Example: {"state":{"balance":"7473303000000", ...}}
          raw_balance_str = data.dig("state", "balance")

          if raw_balance_str.present?
            # Convert raw balance (string of smallest units, 'quanta') to QRL
            # QRL has 9 decimal places (1 QRL = 1,000,000,000 smallest units)
            # Using BigDecimal for precision to avoid floating-point errors
            balance_big_decimal = BigDecimal(raw_balance_str) / BigDecimal("1000000000")
            # Format to a string with exactly 9 decimal places
            formatted_balance = '%.9f' % balance_big_decimal.truncate(9)

            render json: { success: true, qrl_address: address, balance: formatted_balance.to_s }
          else
            # If balance is not found in the expected path, return an error
            render json: { success: false, error: 'Balance data not found in QRL API response.', api_response: data }, status: :internal_server_error
          end
        else
          # If the call to the QRL API fails (e.g., 404, 500), return an appropriate error to the client
          render json: { success: false, error: "Failed to fetch balance from QRL Explorer: #{response.code} - #{response.message}", external_status: response.code }, status: response.code
        end
      rescue JSON::ParserError => e
        # Handle cases where the external API returns invalid JSON
        render json: { success: false, error: "Invalid JSON response from QRL Explorer API: #{e.message}" }, status: :internal_server_error
      rescue StandardError => e
        # Catch any other unexpected errors during the API call
        render json: { success: false, error: "An error occurred while contacting QRL Explorer API: #{e.message}" }, status: :internal_server_error
      end
    end
  end
end