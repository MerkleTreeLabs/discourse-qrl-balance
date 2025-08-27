import { with              } from "@ember/object";
import { inject as service } from "@ember/service";
import Component           from "@ember/component";
import { scheduleOnce      } from "@ember/runloop";
import { empty             } from "@ember/object/computed";

// Extend the Topic model to include the custom field for QRL address.
// This makes `topic.qrlAddress` accessible in client-side Ember models.
api.modifyClass("model:topic", {
  qrlAddress: with.call("topicCustomFields", {
    get(topicCustomFields) {
      return topicCustomFields?.qrl_address;
    },
  }),
});

// Extend the TopicListItem model to include the custom field for QRL address in lists.
// This makes `topic.qrlAddress` accessible in client-side Ember models for topic lists.
api.modifyClass("model:topic-list-item", {
  qrlAddress: with.call("customFields", {
    get(customFields) {
      return customFields?.qrl_address;
    },
  }),
});

// --- Topic View Integration ---
// Decorate the 'topic-status-create-topic' widget to inject our custom component.
// This widget is a good place to add info near the topic title/status.
api.decorateWidget("topic-status-create-topic", (helper) => {
  // Check if the plugin is enabled globally via site settings
  if (SiteSettings.qrl_address_balance_enabled) {
    const qrlAddress = helper.attrs.topic.qrlAddress; // Get the QRL address from the topic's custom field
    const categoryId = helper.attrs.topic.category_id; // Get the topic's category ID
    const designatedCategoryId = SiteSettings.qrl_category_id; // Get the category ID specified in plugin settings

    // If a QRL address is present and the topic is in the designated category,
    // create and return our live balance component.
    if (qrlAddress && categoryId === designatedCategoryId) {
      return helper.h("div.qrl-balance-wrapper", [
        // Create an Ember component to handle the async balance fetching and display
        helper.createCustomComponent("qrl-live-balance", {
          qrlAddress: qrlAddress, // Pass the QRL address to the component
        }),
      ]);
    }
  }
});

// Define the custom Ember component responsible for fetching and displaying the live balance.
api.createCustomComponent("qrl-live-balance", Component.extend({
  qrlAddress: null, // Property to receive the QRL address
  balance: "Loading...", // Initial display text
  lastUpdated: null, // Timestamp of last update
  isError: false, // Flag to indicate an error
  errorMessage: null, // Detailed error message
  timer: null, // Timer for periodic refresh

  // Lifecycle hook: called when the component is inserted into the DOM.
  didInsertElement() {
    this._super(...arguments); // Call parent class's method
    this.fetchBalance(); // Fetch balance immediately
    this.startRefreshTimer(); // Start the periodic refresh timer
  },

  // Lifecycle hook: called when the component is about to be removed from the DOM.
  willDestroyElement() {
    this._super(...arguments);
    this.stopRefreshTimer(); // Stop the timer to prevent memory leaks
  },

  // Starts a timer to periodically fetch the balance.
  startRefreshTimer() {
    const intervalMinutes = SiteSettings.qrl_balance_refresh_interval_minutes;
    if (intervalMinutes > 0) {
      this.timer = setInterval(() => {
        this.fetchBalance();
      }, intervalMinutes * 60 * 1000); // Convert minutes to milliseconds
    }
  },

  // Stops the periodic refresh timer.
  stopRefreshTimer() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  },

  // Async function to fetch the QRL balance.
  async fetchBalance() {
    if (!this.qrlAddress) {
      this.set('balance', 'Invalid QRL Address');
      this.set('isError', true);
      this.set('errorMessage', 'No QRL address provided for lookup.');
      return;
    }

    this.set('isError', false); // Reset error state
    this.set('errorMessage', null);
    this.set('balance', 'Fetching...'); // Show fetching status

    try {
      // Make a request to our server-side proxy route.
      // The proxy will then call the external QRL Explorer API.
      const response = await fetch(`/qrl-proxy/balance/${this.qrlAddress}`);
      const data = await response.json(); // Parse the JSON response

      if (response.ok && data.success) { // Check if HTTP status is OK AND our proxy returned success
        if (data.balance) {
          this.set('balance', `${data.balance} QRL`); // Update balance display
          this.set('lastUpdated', new Date().toLocaleTimeString()); // Update timestamp
        } else {
          // If proxy implies success but no balance,
          // it means balance data was missing from external API.
          this.set('balance', 'Balance data incomplete');
          this.set('errorMessage', data.error || 'Balance data missing from proxy response.');
          this.set('isError', true);
        }
      } else {
        // If HTTP status is not OK OR proxy returned failure
        this.set('balance', 'Error');
        // Use the error message from our proxy, or a generic one based on status
        this.set('errorMessage', data.error || `Failed to fetch balance: Status ${response.status}`);
        this.set('isError', true);
      }
    } catch (error) {
      // Catch network errors or issues connecting to our proxy
      this.set('balance', 'Network Error');
      this.set('errorMessage', `Could not connect to Discourse proxy: ${error.message}`);
      this.set('isError', true);
      console.error("QRL Balance Fetch Error:", error); // Log the full error for debugging
    }
  },

  // Handlebars template for the `qrl-live-balance` component.
  layout: hbs`
    <div class="qrl-balance-display {{if this.isError "error"}}">
      <span class="qrl-balance-label">Current Balance:</span>
      <span class="qrl-balance-value">{{this.balance}}</span>
      {{#if this.lastUpdated}}
        <span class="qrl-balance-timestamp">(Last updated: {{this.lastUpdated}})</span>
      {{/if}}
      {{#if this.isError}}
        <div class="qrl-balance-error-message">{{this.errorMessage}}</div>
      {{/if}}
    </div>
  `,
}));

// --- Topic List View Integration ---
// Decorate the 'topic-list-item-item' widget to show a balance indicator in topic lists.
api.decorateWidget("topic-list-item-item", (helper) => {
  if (SiteSettings.qrl_address_balance_enabled) {
    const topic = helper.attrs; // The topic list item attributes
    const categoryId = topic.category_id;
    const designatedCategoryId = SiteSettings.qrl_category_id;
    const qrlAddress = topic.qrlAddress; // Access the QRL address from the topic list item model

    if (qrlAddress && categoryId === designatedCategoryId) {
      // Create a small Ember component specifically for the list view.
      // This component will fetch and display a concise balance.
      return helper.h("div.qrl-list-balance-wrapper", [
        helper.createCustomComponent("qrl-list-balance-indicator", {
          qrlAddress: qrlAddress,
        }),
      ]);
    }
  }
});

// Define the custom Ember component for the topic list balance indicator.
api.createCustomComponent("qrl-list-balance-indicator", Component.extend({
  qrlAddress: null,
  balance: "...", // Initial display state (e.g., loading indicator)
  isError: false,

  // Called when the component is inserted into the DOM.
  didInsertElement() {
    this._super(...arguments);
    this.fetchBalanceCached(); // Fetch balance
  },

  // Async function to fetch balance for the list item.
  // It uses the same proxy endpoint.
  async fetchBalanceCached() {
    if (!this.qrlAddress) return;

    try {
      const response = await fetch(`/qrl-proxy/balance/${this.qrlAddress}`);
      const data = await response.json();

      if (response.ok && data.success && data.balance) {
        this.set('balance', `${data.balance} QRL`); // Display fetched balance
      } else {
        this.set('balance', 'Err'); // Indicate error concisely
        this.set('isError', true);
        console.error("QRL List Balance Fetch Error:", data.error || `Status: ${response.status}`);
      }
    } catch (error) {
      this.set('balance', 'Net'); // Indicate network error concisely
      this.set('isError', true);
      console.error("QRL List Balance Network Error:", error);
    }
  },

  // Handlebars template for the `qrl-list-balance-indicator` component.
  layout: hbs`
    <span class="qrl-list-balance {{if this.isError "error"}}">
      {{this.balance}}
    </span>
  `,
}));