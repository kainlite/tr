defmodule TrWeb.BeardLive do
  use TrWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col bg-gray-100 dark:bg-gray-900 min-h-screen">
      <div class="w-72 mt-12 h-[21rem] m-auto justify-center">
        <a href="https://www.linkedin.com/in/gabrielgarrido/" target="_blank">
          <img
            src={~p"/images/logo-beard.webp"}
            alt={gettext("Red Beard logo")}
            class="max-h-72 max-w-72 rounded-full scale-125"
          />
        </a>
      </div>

      <section class="text-center mt-8">
        <h2 class="text-2xl font-bold">
          <%= gettext("Get a Free 2-Hour DevOps Assessment — Accelerate Your Cloud
        Transformation Today!") %>
        </h2>
        <p class="text-xl mt-4">
          <%= gettext("Ready to Elevate Your Infrastructure?") %>
          <a href="mailto:gabriel@redbeard.team" class="text-blue-500 underline">
            <%= gettext("Contact us") %>
          </a>
          or
          <a
            href="https://calendar.google.com/calendar/u/0/appointments/schedules/AcZssZ0YS6qO3d2Aj9SpjMGPnxHFXZmXMj8YRgE5VO_aRaqUb23J2qS8ISCJK0dAzmWZa7fW-WJe1OCU?gv=true"
            class="text-blue-500 underline"
            target="_blank"
          >
            <%= gettext("Schedule a call Now!") %>
          </a>
        </p>
        <p class="text-lg mt-4">
          <%= gettext(
            "Expert Support on Your Cloud Journey — from Innovative Architecture to Robust Security —
          Specializing in Automation and Best Practices."
          ) %>
        </p>

        <p class="text-lg mt-4">
          <%= gettext(
            "DevOps on demand, need help with linux, CI/CD, Docker, Kubernetes, AWS, send us a message."
          ) %>
        </p>
        <br />

        <h4 class="mx-auto"><%= gettext("Flexible Engagement Models Tailored to Your Needs") %></h4>
        <p class="text-lg mt-2">
          <ul class="list-outside mt-2 text-left inline-block ml-60">
            <li>
              <%= gettext(
                "Fractional Services: Access high-level expertise without the full-time cost."
              ) %>
            </li>
            <li>
              <%= gettext("Project-Based Contracts: Define objectives and outcomes upfront.") %>
            </li>
            <li>
              <%= gettext(
                "Part-Time Consulting: Expertise on a part-time basis fixed hours per day dedicated
            exclusively to you."
              ) %>
            </li>
            <li><%= gettext("Full-Time Consulting: Dedicated support for your team.") %></li>
          </ul>
        </p>

        <h4 class="mx-auto"><%= gettext("Wondering how we can help you?") %></h4>
        <p class="text-lg mt-2">
          <ul class="list-outside mt-2 text-left inline-block ml-60">
            <li>
              <%= gettext("Audit and validate your architecture, ask yourself:") %>
              <ul>
                <li>
                  <%= gettext(
                    "is our infrastructure secure? do we have the right security groups, access control lists,
                  policies? encryption in place?"
                  ) %>
                </li>
                <li>
                  <%= gettext(
                    "Does our network have the capacity to grow and connect to other environments?"
                  ) %>
                </li>
                <li>
                  <%= gettext("is our infrastructure cost efficient?") %>
                </li>
              </ul>
            </li>
            <li>
              <%= gettext("Migrate projects to the cloud or back on-premises") %>
            </li>
            <li>
              <%= gettext(
                "Optimize and automate processes to free your team from repetitive, time-consuming tasks"
              ) %>
            </li>
            <li>
              <%= gettext(
                "Establish conventions and best practices to ensure consistency and scalability"
              ) %>
            </li>
            <li>
              <%= gettext("Set up observability and monitoring") %>
              <ul>
                <li>
                  <%= gettext("is our app fast and reliable?") %>
                </li>
                <li>
                  <%= gettext("are we caching data efficiently (or at all)?") %>
                </li>
                <li>
                  <%= gettext("Is the database properly sized? Do we have working backups?") %>
                </li>
              </ul>
            </li>
            <li>
              <%= gettext(
                "We can help you find answers to these questions and so much more. Schedule a call and let’s get started!"
              ) %>
            </li>
          </ul>
        </p>

        <br />
        <h3 class="text-xl font-bold">
          <% locale = if Gettext.get_locale(TrWeb.Gettext) == "en", do: "es", else: "en" %>
          <%= gettext("Looking for the ") %>
          <.link aria-label="language-toggle" navigate={~p"/#{locale}"}>
            <%= gettext("spanish") %>
          </.link>
          <%= gettext("version?") %>

          <%= gettext("Or the ") %><a href={~p"/#{Gettext.get_locale(TrWeb.Gettext)}/blog"}>blog?</a>
        </h3>
      </section>

      <section class="mt-12 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 px-8">
        <div
          id="architecture"
          class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-lg rounded-lg overflow-hidden"
        >
          <img
            src={~p"/images/architecture.png"}
            alt={gettext("Cloud Architecture")}
            class="w-full h-56 object-cover"
          />
          <div class="p-6">
            <h3 class="text-xl font-bold"><%= gettext("Cloud Architecture") %></h3>
            <p class="mt-2 text-gray-700 dark:text-gray-300">
              <%= gettext(
                "Designing Robust, Scalable, and Secure Cloud Infrastructures for optimized performance across AWS and Azure."
              ) %>
            </p>
          </div>
        </div>

        <div
          id="iac"
          class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-lg rounded-lg overflow-hidden"
        >
          <img
            src={~p"/images/terraform-workflow.png"}
            alt={gettext("Infrastructure as Code")}
            class="w-full h-56 object-cover"
          />
          <div class="p-6">
            <h3 class="text-xl font-bold"><%= gettext("Infrastructure as Code") %></h3>
            <p class="mt-2 text-gray-700 dark:text-gray-300">
              <%= gettext(
                "Automate, Simplify, and Scale Your Infrastructure with Terraform, Pulumi, and Ansible."
              ) %>
            </p>
          </div>
        </div>

        <div
          id="containers"
          class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-lg rounded-lg overflow-hidden"
        >
          <img
            src={~p"/images/docker-kubernetes.png"}
            alt={gettext("Containerization and Orchestration")}
            class="w-full h-56
          object-fill"
          />
          <div class="p-6">
            <h3 class="text-xl font-bold"><%= gettext("Containerization and Orchestration") %></h3>
            <p class="mt-2 text-gray-700 dark:text-gray-300">
              <%= gettext(
                "Streamline Application Deployment with Docker and Kubernetes for scalable, portable solutions."
              ) %>
            </p>
          </div>
        </div>

        <div
          id="cicd"
          class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-lg rounded-lg overflow-hidden"
        >
          <img
            src={~p"/images/github-actions.png"}
            alt={gettext("CI/CD Pipelines")}
            class="w-full h-56 object-cover"
          />
          <div class="p-6">
            <h3 class="text-xl font-bold"><%= gettext("CI/CD Pipelines") %></h3>
            <p class="mt-2 text-gray-700 dark:text-gray-300">
              <%= gettext(
                "Accelerate Software Delivery with Automated CI/CD Solutions using GitHub Actions, GitLab, and
              ArgoCD."
              ) %>
            </p>
          </div>
        </div>

        <div
          id="monitoring"
          class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-lg rounded-lg overflow-hidden"
        >
          <img
            src={~p"/images/prometheus-dashboards.png"}
            alt={gettext("Observability and Monitoring")}
            class="w-full h-56 object-cover"
          />
          <div class="p-6">
            <h3 class="text-xl font-bold"><%= gettext("Observability and Monitoring") %></h3>
            <p class="mt-2 text-gray-700 dark:text-gray-300">
              <%= gettext(
                "Gain full visibility with comprehensive monitoring tools like Datadog, Prometheus, and
              Grafana."
              ) %>
            </p>
          </div>
        </div>

        <div
          id="security"
          class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-lg rounded-lg overflow-hidden"
        >
          <img
            src={~p"/images/cybersecurity.webp"}
            alt={gettext("Integrated Security")}
            class="w-full h-56 object-cover"
          />
          <div class="p-6">
            <h3 class="text-xl font-bold"><%= gettext("Integrated Security") %></h3>
            <p class="mt-2 text-gray-700 dark:text-gray-300">
              <%= gettext(
                "Embed robust security throughout your infrastructure with secure architecture, IaC, and
              compliance solutions."
              ) %>
            </p>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
