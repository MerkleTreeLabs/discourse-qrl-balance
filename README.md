# ✨ QRL Address Balance Plugin for Discourse ✨

Elevate your Discourse community by seamlessly integrating real-time QRL blockchain data directly into your topics! The QRL Address Balance Plugin empowers you to display the current fund balance of any QRL address within your designated categories, providing dynamic, up-to-date information at a glance.

Imagine: A community hub where members can easily track project treasuries, bounty progress, or simply monitor key QRL addresses, all within the familiar and engaging environment of Discourse. This plugin makes it a reality!

## 🚀 Features

*   **Real-Time Balance Display:** Fetches and displays the live fund balance of a specified QRL address within a topic.
*   **Server-Side Proxy:** Securely connects to the QRL public explorer API through your Discourse server, bypassing browser CORS restrictions and ensuring reliable data retrieval.
*   **Configurable Categories:** Choose which Discourse categories will utilize this exciting feature.
*   **Automatic Refresh:** Balances automatically refresh on a configurable interval when the topic page is active, ensuring information stays current.
*   **Topic List Integration:** Provides a concise balance indicator directly in the topic list for quick overview, perfect for dedicated tracking categories.
*   **Precision and Accuracy:** Handles QRL's 9 decimal place precision, displaying exact balances.
*   **Easy Configuration:** Simple setup via Discourse's intuitive Admin / Settings interface.

## 🌟 Why You'll Love It

This plugin isn't just about displaying numbers; it's about fostering transparency, engagement, and a deeper connection to the QRL ecosystem within your community. Whether you're running bounties, managing community funds, or simply want to track important addresses, this plugin provides the perfect solution, enhancing your Discourse forum's utility and appeal.

## 🛠️ Installation

Installing the QRL Address Balance Plugin is straightforward. Follow these steps to get it up and running on your Discourse instance.

### System Requirements

*   **Discourse Version:** This plugin is designed for Discourse versions `2.8.0` and above. While it might work with slightly older versions, `2.8.0` is the recommended minimum for full compatibility with plugin APIs used. It has been tested against the latest stable Discourse versions.
*   **QRL Explorer API:** Requires access to a QRL public explorer API that provides address information (e.g., `https://explorer.theqrl.org/api/`).

### Steps

1.  **SSH into your Discourse server.**

2.  **Navigate to your Discourse `plugins` directory:**
    ```bash
    cd /var/www/discourse/plugins
    ```

3.  **Clone the plugin repository:**
    ```bash
    git clone https://github.com/MerkleTreeLabs/Discorse-QRL-Balance.git
    ```

4.  **Edit your `app.yml` file:**
    ```bash
    cd /var/www/discourse
    nano containers/app.yml # or vim containers/app.yml
    ```
    Add or ensure the following line is present in the `plugins` section:
    ```yaml
    ## Plugins
    ## see https://github.com/discourse/discourse/blob/master/lib/plugin/README.md
    plugins:
      # ... other plugins you may have ...
      - git clone https://github.com/your-username/discourse-qrl-address-balance.git # <--- This line
    ```
    Save and exit the editor (`Ctrl+X`, `Y`, `Enter` for nano).

5.  **Rebuild your Discourse container:**
    ```bash
    ./launcher rebuild app
    ```
    This process will take some time as Discourse rebuilds its image and installs the plugin.

6.  **Configure the Plugin in Discourse Admin:**
    *   Once the rebuild is complete, log in to your Discourse forum as an **administrator**.
    *   Navigate to **Admin (wrench icon) > Settings > Plugins**.
    *   Find the "QRL Address Balance" plugin.
    *   **Enable** the plugin by checking the `qrl address balance enabled` checkbox.
    *   **QRL Explorer Base URL:** Set this to `https://explorer.theqrl.org` (this is the base URL for the public QRL explorer API).
    *   **QRL Category ID:** Select the Discourse category where you want to display the QRL address balances. Topics within this category will have the special functionality.
    *   **QRL Balance Refresh Interval Minutes:** Set how often the balance should refresh on the topic page (e.g., 5 minutes).
    *   Click "Save Changes".

## 🚀 Usage

Once configured, using the QRL Address Balance Plugin is simple:

1.  **Create or Edit a Topic** in the category you designated in the plugin settings (e.g., "Treasury Tracking," "Bounties," etc.).
2.  While editing the topic, look for the **"Custom Fields"** section (usually below the main post editor).
3.  You will find a field labeled **`qrl_address`**.
4.  **Enter the full QRL address** into this field (e.g., `Q010500888ad868e2969380b190796be62991407721d12280de4eeae3a6bf39aac5637109b788e4`).
5.  **Save the topic.**

Now, when any user views this topic, they will see an elegant box displaying the current QRL balance for the specified address, automatically updating at the set interval! Additionally, a concise balance indicator will appear next to the topic title in the topic list of that category.


## 📂 Plugin File Structure

```
discourse-qrl-address-balance/
├── assets/
│   ├── javascripts/
│   │   └── discourse/
│   │       └── initializers/
│   │           └── qrl-address-balance.js.es6
│   └── stylesheets/
│       └── common/
│           └── qrl-address-balance.scss
├── plugin.rb
└── README.md (This file)
```


## 🤝 Contributing

We welcome contributions to make this plugin even better! If you have suggestions, bug reports, or want to contribute code, please open an issue or pull request on the GitHub repository.