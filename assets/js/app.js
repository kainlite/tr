// app.js
// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import * as CookieConsent from "../vendor/cookieconsent.esm";

let Hooks = {};
Hooks.Scroll = {
  mounted() {
    this.el.addEventListener("click", () => {
      document.getElementById("comment_form").scrollIntoView();
    });
  },
};

Hooks.CopyToClipboard = {
  mounted() {
    this.run();
  },
  reconnected() {
    this.run();
  },
  run() {
    const copyButtonLabel = "Copy Code";

    // use a class selector if available
    let blocks = document.querySelectorAll("pre");

    blocks.forEach((block) => {
      // only add button if browser supports Clipboard API
      if (navigator.clipboard) {
        let button = document.createElement("button");

        button.innerText = copyButtonLabel;
        block.appendChild(button);

        button.addEventListener("click", async () => {
          await copyCode(block, button);
        });
      }
    });

    async function copyCode(block, button) {
      let code = block.querySelector("code");
      let text = code.innerText;

      try {
        await navigator.clipboard.writeText(text);

        // visual feedback that task is completed
        button.innerText = "Code Copied";

        setTimeout(() => {
          button.innerText = copyButtonLabel;
        }, 700);
      } catch (err) {
        console.error("Failed to copy text: ", err);
        button.innerText = "Copy failed";

        setTimeout(() => {
          button.innerText = copyButtonLabel;
        }, 700);
      }
    }
  },
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

liveSocket.disableDebug();
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
  // enable server log streaming to client.
  // disable with reloader.disableServerLogs()
  reloader.enableServerLogs();
});

// https://elixirforum.com/t/how-to-add-dark-mode-for-phoenix-1-7/54356/3
function darkExpected() {
  return (
    localStorage.theme === "dark" ||
    (!("theme" in localStorage) &&
      window.matchMedia("(prefers-color-scheme: dark)").matches)
  );
}

function initDarkMode() {
  // On page load or when changing themes, best to add inline in `head` to avoid FOUC
  if (darkExpected()) {
    document.documentElement.classList.add("dark");
    document.documentElement.classList.add("cc--darkmode");
  } else {
    document.documentElement.classList.remove("dark");
    document.documentElement.classList.remove("cc--darkmode");
  }
}

window.addEventListener("toogle-darkmode", (e) => {
  if (darkExpected()) {
    localStorage.theme = "light";
    document.documentElement.style.setProperty("color-scheme", "light");
  } else {
    localStorage.theme = "dark";
    document.documentElement.style.setProperty("color-scheme", "dark");
  }
  initDarkMode();
});

initDarkMode();

defaultLanguage = "en";
if (window.location.href.indexOf("/es/") != -1) {
  defaultLanguage = "es";
}

CookieConsent.run({
  guiOptions: {
    consentModal: {
      layout: "box wide",
      position: "bottom right",
      equalWeightButtons: true,
      flipButtons: false,
    },
    preferencesModal: {
      layout: "box",
      position: "right",
      equalWeightButtons: true,
      flipButtons: false,
    },
  },
  categories: {
    necessary: {
      readOnly: true,
    },
    marketing: {
      readOnly: true,
    },
  },
  language: {
    default: defaultLanguage,
    autoDetect: "browser",
    translations: {
      es: {
        consentModal: {
          title: "Hola!",
          description:
            "Por favor acepta el uso de cookies para poder seguir navegando en nuestro sitio.",
          acceptAllBtn: "Aceptar todo",
          showPreferencesBtn: "Preferencias",
          footer:
            '<a href="https://redbeard.team/privacy">Politica de privacidad</a>',
        },
        preferencesModal: {
          title: "Consentimiento de cookies",
          acceptAllBtn: "Aceptar todo",
          savePreferencesBtn: "Guardar",
          closeIconLabel: "Cerrar",
          serviceCounterLabel: "Servicio|Servicios",
          sections: [
            {
              title: "Uso de cookies",
              description:
                "Utilizamos únicamente las cookies necesarias para garantizar el correcto funcionamiento del sitio web y para ejecutar 1 anuncio por página. Como el contenido es gratuito, esto es un incentivo para que todo siga funcionando. Solo hay tres cookies que puede ver: una es para mantener la información de su sesión (puramente funcional) y la segunda es una cookie seudoanónima creada por AdsTerra para ejecutar los anuncios en el sitio. La tercera cookie es cc_cookie, que se utiliza para guardar sus preferencias de cookies. Al utilizar este sitio, acepta los términos de privacidad de este sitio y mantener estas cookies mientras utilice el sitio",
            },
            {
              title: "Mas informacion",
              description:
                'Por cualquier consulta relacionada al sitio o las cookies, por favor contactarnos aqui <a class="cc__link" href="mailto:gabriel@redbeard.team">gabriel@redbeard.team</a>.',
            },
          ],
        },
      },
      en: {
        consentModal: {
          title: "Hello blogger!",
          description:
            "Please accept the usage of cookies to be able to continue browsing our site.",
          acceptAllBtn: "Accept all",
          showPreferencesBtn: "Manage preferences",
          footer: '<a href="https://redbeard.team/privacy">Privacy Policy</a>',
        },
        preferencesModal: {
          title: "Consent Preferences Center",
          acceptAllBtn: "Accept all",
          savePreferencesBtn: "Save preferences",
          closeIconLabel: "Close modal",
          serviceCounterLabel: "Service|Services",
          sections: [
            {
              title: "Cookie Usage",
              description:
                "We use only necessary cookies to ensure the website works properly, and to run 1 ad per page, as the content is free this is an incentive to keep everything running. There are only three cookies that you might see one is to maintain your session information (purely functional), and the second one is a pseudoanonymous cookie created by AdsTerra to run the ads in the site, the third cookie is cc_cookie which is used to save your cookie preferences, by using this site you are agreeing to the privacy terms from this site and to keep these cookies as long as you are using the site.",
            },
            {
              title: "More information",
              description:
                'For any query in relation to my policy on cookies and your choices, please <a class="cc__link" href="mailto:gabriel@redbeard.team">gabriel@redbeard.team</a>.',
            },
          ],
        },
      },
    },
  },
});
