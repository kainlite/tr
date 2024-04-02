defmodule TrWeb.HomeLive do
  use TrWeb, :live_view

  alias Tr.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :posts, Blog.recent_posts())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="phx-hero">
      <h1>Welcome to the laboratory</h1>
      <p>Be brave, explore the unknown...</p>
    </section>
    <p>
      This blog was created to document and learn about different technologies, among other things it has been deployed to a
      k3s cluster running in OCI, using elixir and the phoenix framework, postgres, docker, kubernetes on ARM64, and many other things,
      if that sounds interesting, you can follow me on twitter or create an account here to receive new posts notifications
      and later on a newsletter, so I hope you enjoy your stay and see you on the other side...
    </p>

    <div class="flex">
      <div class="m-auto pb-[10px]">
        <%= unless @current_user do %>
          <.link navigate={~p"/users/register"} class="text-[1.25rem] button h-auto w-[217px]">
            Subscribe
          </.link>
        <% end %>
        <a href="https://www.buymeacoffee.com/NDx5OFh" target="_blank" class="">
          <img
            src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
            alt="Buy Me A Coffee"
            style="height: 60px !important;width: 217px !important;"
          />
        </a>
      </div>
    </div>
    <div class="flex">
      <div class="m-auto">
        <p class="text-[1.2rem] justify-center">
          Feel free to register (subscribe) to receive a monthly newsletter related to the topics on this blog and a
          notification on new articles (you can unsubscribe at any time from the settings page), in the future I expect to
          develop more features that rely on authentication, so the earlier is set the easiest will be later on.
        </p>
        <br />
      </div>
    </div>

    <section class="row">
      <article class="column">
        <h2>Latest articles</h2>

        <ul>
          <%= for post <- @posts do %>
            <div>
              <li>
                <.link navigate={~p"/blog/#{post.id}"}>
                  <%= post.title %>
                </.link>
              </li>
            </div>
          <% end %>
        </ul>
      </article>

      <article class="column">
        <h2>Resources</h2>
        <ul>
          <li>
            <a href="https://techsquad.rocks/blog">This blog</a>
          </li>
          <li>
            <a href="https://github.com/kainlite/tr">Github repository</a>
          </li>
          <li>
            <a href="https://twitter.com/kainlite">Twitter @kainlite</a>
          </li>
          <li>
            <.link
              rel="alternate"
              type="application/rss+xml"
              title="Blog Title"
              navigate={~p"/index.xml"}
            >
              RSS
            </.link>
          </li>
          <li>
            <.link navigate={~p"/privacy"}>
              Privacy policy
            </.link>
          </li>
        </ul>
      </article>
    </section>
    """
  end

  def privacy(assigns) do
    ~H"""
    <div>
      <h1>Privacy Policy</h1>
      Last updated: March 17, 2024
      <p>
        At TechSquad.rocks, we are committed to safeguarding the privacy of your data. In this policy, we articulate what data
        we collect, why we collect it, how your data is handled, and your rights concerning your data. We assure you that we
        will never sell your data.
      </p>

      <h3>Disclosure</h3>
      <p>
        The examples, code snippets, and blog articles provided herein are offered for educational or illustrative purposes
        only. Any reliance on the information contained within is at your own discretion and risk. We assume no responsibility
        for the accuracy, completeness, or suitability of the content provided. Additionally, use of any code snippets or
        implementation examples should be thoroughly reviewed and tested in your own environment before implementation in a
        production setting. We disclaim any liability for any damages or losses incurred as a result of using or relying on
        the information presented.

        All code and examples provided within this context are released under the MIT License unless otherwise stated. The MIT
        License grants you permission to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
        software and associated documentation files without restriction, provided that the above copyright notice and this
        permission notice appear in all copies or substantial portions of the software. The software and examples are provided
        "as is", without warranty of any kind, express or implied, including but not limited to the warranties of
        merchantability, fitness for a particular purpose, and noninfringement. In no event shall the authors or copyright
        holders be liable for any claim, damages, or other liability, whether in an action of contract, tort, or otherwise,
        arising from, out of, or in connection with the software or the use or other dealings in the software.
      </p>

      <h3>Information Collection and Purpose</h3>

      <p>
        Our fundamental principle is to collect only essential information necessary to provide you with the services you
        have signed up for. We utilize a carefully selected group of trusted external service providers for specific offerings.
        These providers adhere to high standards of data protection, privacy, and security. We only share information necessary
        for the services provided.
      </p>

      <h2>Here's how this translates into practice:</h2>

      <h3>Identity & Access</h3>

      <p>
        When you register for an account with TechSquad.rocks,  we collect minimal information about you in order to
        authenticate and authorize your use of TechSquad.rocks. This includes your your email, password and display name.

        We do not sell your personal information to third parties, nor do we use your name or company in
        marketing statements unless agreed beforehand.
      </p>

      <h3>Geolocation Data</h3>

      <p>
        We do not maintain a record of your IP address nor your connections.
      </p>

      <h3>Website Interactions</h3>

      <p>
        We utilize might utilize Google Analytics later on, to analyze overall trends in website usage.
        Transactional emails are sent to authenticated users through Brevo as our provider.
      </p>

      <h3>Cookies</h3>

      <p>
        At the moment we don't have any third-party cookie, but we might add Google Analytics soon. Additionally, a cookie is
        stored when logging in to identify your account on the blog and selecting the "Remember me" option, remaining until expiration.
      </p>

      <h3>Voluntary Correspondence</h3>

      <p>
        Correspondences with TechSquad.rocks, including email addresses, are retained to maintain a history of past
        communications for reference in future interactions.
      </p>

      <h3>Information We Do Not Collect</h3>

      <p>
        We do not collect characteristics of protected classifications such as age, race, gender, religion, sexual
        orientation, gender identity, gender expression, or physical and mental abilities or disabilities. Furthermore, we do
        not collect any biometric data and display only the profile photo provided in your platform without extracting
        additional information.
      </p>

      <h3>Data Security Measures</h3>

      <p>
        At TechSquad.rocks, we prioritize the security of your data through comprehensive measures:

        Encryption: All data transmitted to your browser from our servers hosted on Oracle OCI is encrypted using SSL/TLS
        protocols.

        Database Architecture: Our database modeling architecture employs a very simple strategy which is sinlge-tenant and
        self managed.

        Please refer to the Oracle OCI Security Policy for more information on their security practices.
      </p>

      <h3>Data Deletion Process</h3>

      <p>
        Account Closure: Upon closure of your TechSquad.rocks account, we ensure the permanent deletion of all your data from
        our live database. Data held in backups may persist until those backups are purged.
      </p>

      <h3>Location of Site and Data</h3>

      <p>
        The primary data shared with us is stored on servers provided by Oracle Cloud in the United States. Please refer to
        the privacy policies of our third-party providers for information regarding the location and storage of data.
      </p>

      <h3>Data Retention</h3>

      <p>
        We retain your information for as long as your account is active, as necessary to provide you with our services, or as
        outlined in this policy. Additionally, we may retain and use your information as necessary to comply with legal
        obligations, resolve disputes, enforce agreements, and protect TechSquad.rocks' legal rights.

        You can choose to delete your TechSquad.rocks account at any time by contacting us at
        support@techsquad.rocks. Upon approval, we will permanently delete all your data from our live database. Data in
        backups may persist until those backups are purged.

        At a later stage we will provide you with the necessary tools to self-delete your account and all your data.
      </p>

      <h3>Changes and Questions</h3>

      <p>
        We may update this policy as needed to comply with relevant regulations and reflect any new practices. Significant
        changes to our policies will be announced on our blog and/or dashboard.

        If you have any questions, comments, or concerns regarding this privacy policy, your data, or your rights concerning
        your information, please don't hesitate to contact us at support@techsquad.rocks, and we will be happy to assist you.
      </p>
    </div>
    """
  end
end
