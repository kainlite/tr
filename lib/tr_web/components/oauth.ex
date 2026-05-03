defmodule TrWeb.OAuthComponent do
  @moduledoc """
  Renders OAuth provider sign-in buttons (Google, GitHub) with terminal styling.
  """
  use Phoenix.Component
  use Gettext, backend: TrWeb.Gettext

  attr :oauth_google_url, :string, required: true
  attr :oauth_github_url, :string, required: true

  def buttons(assigns) do
    ~H"""
    <div class="my-6 space-y-3">
      <a
        href={@oauth_google_url}
        class="flex items-center justify-center gap-3 w-full px-4 py-2.5
               border border-terminal-300 dark:border-terminal-600
               bg-terminal-50 dark:bg-terminal-800
               hover:bg-terminal-100 dark:hover:bg-terminal-700
               font-mono text-sm text-zinc-900 dark:text-zinc-100
               no-underline transition-colors"
      >
        <svg class="w-5 h-5" viewBox="0 0 533.5 544.3" xmlns="http://www.w3.org/2000/svg">
          <path
            d="M533.5 278.4c0-18.5-1.5-37.1-4.7-55.3H272.1v104.8h147c-6.1 33.8-25.7 63.7-54.4 82.7v68h87.7c51.5-47.4 81.1-117.4 81.1-200.2z"
            fill="#4285f4"
          />
          <path
            d="M272.1 544.3c73.4 0 135.3-24.1 180.4-65.7l-87.7-68c-24.4 16.6-55.9 26-92.6 26-71 0-131.2-47.9-152.8-112.3H28.9v70.1c46.2 91.9 140.3 149.9 243.2 149.9z"
            fill="#34a853"
          />
          <path
            d="M119.3 324.3c-11.4-33.8-11.4-70.4 0-104.2V150H28.9c-38.6 76.9-38.6 167.5 0 244.4l90.4-70.1z"
            fill="#fbbc04"
          />
          <path
            d="M272.1 107.7c38.8-.6 76.3 14 104.4 40.8l77.7-77.7C405 24.6 339.7-.8 272.1 0 169.2 0 75.1 58 28.9 150l90.4 70.1c21.5-64.5 81.8-112.4 152.8-112.4z"
            fill="#ea4335"
          />
        </svg>
        <span>{gettext("Continue with Google")}</span>
      </a>

      <a
        href={@oauth_github_url}
        class="flex items-center justify-center gap-3 w-full px-4 py-2.5
               border border-terminal-300 dark:border-terminal-600
               bg-terminal-50 dark:bg-terminal-800
               hover:bg-terminal-100 dark:hover:bg-terminal-700
               font-mono text-sm text-zinc-900 dark:text-zinc-100
               no-underline transition-colors"
      >
        <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <path
            fill-rule="evenodd"
            clip-rule="evenodd"
            d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.337c1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.017C22 6.484 17.522 2 12 2z"
          />
        </svg>
        <span>{gettext("Continue with GitHub")}</span>
      </a>

      <div class="flex items-center gap-3 my-2">
        <div class="flex-1 border-t border-terminal-300 dark:border-terminal-600"></div>
        <span class="font-mono text-xs text-terminal-400 uppercase tracking-wider">
          {gettext("or")}
        </span>
        <div class="flex-1 border-t border-terminal-300 dark:border-terminal-600"></div>
      </div>
    </div>
    """
  end
end
