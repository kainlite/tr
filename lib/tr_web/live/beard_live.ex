defmodule TrWeb.BeardLive do
  use TrWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div class="w-72 mt-12 h-[21rem] m-auto justify-center">
        <img
          src={~p"/images/logo-beard.webp"}
          alt="Red Beard logo"
          class="max-h-72 max-w-72 rounded-full scale-125"
        />
      </div>

      <div class="flex flex-col">
        <div class="m-auto">
          <div class="justify-center text-center">
            <span class="font-bold">Free 2 hours assessment for your project, get in touch!</span>
            <p class="text-[1.4rem] justify-center font-semibold">
              <a href="mailto:gabriel@redbeard.team" class=" h-auto w-[217px]">
                Contact us
              </a>
              or
              <link href="https://assets.calendly.com/assets/external/widget.css" rel="stylesheet" />
              <script
                src="https://assets.calendly.com/assets/external/widget.js"
                type="text/javascript"
                async
              >
              </script>
              <a
                href=""
                onclick="Calendly.initPopupWidget({url: 'https://calendly.com/kainlite/15min'});return false;"
              >
                Schedule time with us
              </a>
            </p>
            <p class="text-[1.4rem] justify-center font-semibold">
              We support you in your cloud journey, from architecture to security, with a focus on automation and best practices.
            </p>

            <br />

            <p class="text-[1.4rem] justify-center font-semibold">
              We support different working methodologies, to match what your company needs:
              <ul>
                <li class="text-[1.4rem] justify-center font-semibold">Per hour billing</li>
                <li class="text-[1.4rem] justify-center font-semibold">Per project or objective</li>
                <li class="text-[1.4rem] justify-center font-semibold">As part-time consultants</li>
                <li class="text-[1.4rem] justify-center font-semibold">As full-time consultants</li>
              </ul>
            </p>
          </div>
          <div class="flex flex-row flex-wrap columns-3 text-center justify-center">
            <div id="architecture">
              <div class="relative">
                <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
                    h-[24rem] m-4">
                  <div class="p-6">
                    <h3>Architecture</h3>
                    <p class="mx-auto sm:text-base sm:leading-7">
                      At Red Beard, we specialize in designing and implementing robust, scalable, and secure cloud infrastructures tailored to meet your business needs.
                      Our cloud architecture services encompass a comprehensive approach, from initial strategy and planning to deployment and ongoing optimization.
                      We ensure your infrastructure is not only aligned with industry best practices but also optimized for performance, cost-efficiency, and security.
                      Whether you're migrating to the cloud, modernizing your existing systems, or building from the ground up, our team of experts leverages leading cloud platforms like AWS, Azure, and Google Cloud to deliver a resilient and future-proof architecture.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div id="iac">
              <div class="relative">
                <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
                    h-[24rem] m-4">
                  <div class="p-6">
                    <h3>Infrastructure as code</h3>
                    <p class="mx-auto sm:text-base sm:leading-7">
                      Red Beard empowers your organization with Infrastructure as Code (IaC), enabling you to manage and provision your entire infrastructure through code.
                      By automating the setup and management of your infrastructure, we eliminate manual processes, reduce errors, and ensure consistency across your environments.
                      Our IaC services include the design, implementation, and maintenance of infrastructure using tools
                      like Terraform, Pulumi, and Ansible.
                      This approach not only accelerates deployment times but also enhances scalability, security, and reliability, allowing your teams to focus on innovation rather than infrastructure management.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div id="containers">
              <div class="relative">
                <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
                    h-[24rem] m-4">
                  <div class="p-6">
                    <h3>Containers</h3>
                    <p class="mx-auto sm:text-base sm:leading-7">
                      At Red Beard, we streamline your application deployment and management through expert containerization and Kubernetes services.
                      We design, implement, and optimize containerized environments to ensure scalability, reliability, and ease of management.
                      Our team leverages Kubernetes to orchestrate your containers, automate deployments, and enhance resilience, enabling your applications to thrive in dynamic cloud environments.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div id="cicd">
              <div class="relative">
                <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
                    h-[24rem] m-4">
                  <div class="p-6">
                    <h3>CI/CD Pipelines</h3>
                    <p class="mx-auto sm:text-base sm:leading-7">
                      Red Beard accelerates your software development lifecycle with our Continuous Integration and Continuous Deployment (CI/CD) services.
                      We design and implement CI/CD pipelines that automate testing, integration, and deployment, ensuring faster delivery of high-quality code.
                      By streamlining these processes, we help your teams release features more efficiently, reduce downtime, and maintain a competitive edge.
                      Our main tools are Github Actions, Gitlab CI/CD, ArgoCD, among others.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div id="monitoring">
              <div class="relative">
                <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
                    h-[24rem] m-4">
                  <div class="p-6">
                    <h3>Observability and monitoring</h3>
                    <p class="mx-auto sm:text-base sm:leading-7">
                      At Red Beard, we provide comprehensive monitoring and observability solutions to ensure the health and performance of your infrastructure and applications.
                      Utilizing tools like Datadog, Grafana, Prometheus, or your preferred platform, we set up robust monitoring systems that offer real-time insights, alerting, and analytics.
                      Our services help you proactively identify issues, optimize performance, and maintain system reliability, giving you full visibility into your operations.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div id="security">
              <div class="relative">
                <div class="bg-white dark:bg-zinc-700 dark:text-gray-200 shadow-md rounded-lg overflow-hidden w-[39rem]
                    h-[24rem] m-4">
                  <div class="p-6">
                    <h3>Security</h3>
                    <p class="mx-auto sm:text-base sm:leading-7">
                      Security is at the core of every service we provide at Red Beard.
                      We integrate robust security practices into every aspect of your infrastructure, from cloud architecture and IaC to CI/CD pipelines and monitoring.
                      Our approach ensures that security is a continuous focus, with proactive measures implemented at every stage of your development and deployment processes.
                      By embedding security into your workflows, we help safeguard your data, applications, and infrastructure against evolving threats, ensuring compliance and peace of mind.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
