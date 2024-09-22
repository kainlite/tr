%{
  title: "How to report your gmail spam folder to spamcop",
  author: "Gabriel Garrido",
  description: "This post is a bit different from the others in the sense that it's a small tool I did to ease spam reporting to...",
  tags: ~w(golang linux),
  published: true,
  image: "spam.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![spam](/images/spam.png){:class="mx-auto"}

##### **Introduction**
This post is a bit different from the others in the sense that it's a small "tool" I did to ease spam reporting to [SpamCop.net](https://www.spamcop.net/), this helps to reduce the true Spam from unknown sources, since for some reason I started to get like 40 emails per day (all went to spam), but it is still somewhat annoying, so I started reporting it to spamcop, but the process was kind of slow and I got tired of that quickly, so I created this "script" to make things easier. Basically what it does is list all messages in the spam folders fetches them and then forwards each one as an attachment to spamcop, then you get an email with a link to confirm the submission and that's it.
<br />

There are a few pre-requisites, like enabling the GMail API for your account, you can do that [here](https://developers.google.com/gmail/api/quickstart/go#step_1_turn_on_the), after that the first time you use the app you have to authorize it, you do this by pasting the URL that the app gives you in the browser, then clicking Allow, and then pasting the token that it gives you back in the terminal (this only needs to be done once), after that you just run the binary in a cronjob or maybe even as a lambda (but I haven't gone there yet), I usually check the spam folder remove what I don't think it's spam or whatever and then run the script to report everything else that it is clearly spam, it takes a few seconds and then I get the link to confirm all reports (one by one, sadly), this script is not perfect as sometimes spamcop cannot read properly the forwarded email, but I have checked exporting those as a file and I do see them all right, so that will be an investigation for another day, this only took like 2-4 hours, having 0 knowledge of the GMail API, etc.
<br />

Also you need to setup a spamcop account which you will be using to send your reports, you can do that [here](https://www.spamcop.net/anonsignup.shtml)
<br />

The source code can be found [here](https://github.com/kainlite/spamcop)
<br />

##### **Code**
I have added some comments along the code to make things easy to understand
```elixir
package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"

	"golang.org/x/net/context"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/gmail/v1"
)

// Retrieve a token, saves the token, then returns the generated client.
func getClient(config *oauth2.Config) *http.Client {
	// The file token.json stores the user's access and refresh tokens, and is
	// created automatically when the authorization flow completes for the first
	// time.
	tokFile := "token.json"
	tok, err := tokenFromFile(tokFile)
	if err != nil {
		tok = getTokenFromWeb(config)
		saveToken(tokFile, tok)
	}
	return config.Client(context.Background(), tok)
}

// Request a token from the web, then returns the retrieved token.
func getTokenFromWeb(config *oauth2.Config) *oauth2.Token {
	authURL := config.AuthCodeURL("state-token", oauth2.AccessTypeOffline)
	fmt.Printf("Go to the following link in your browser then type the "+
		"authorization code: 
%v
", authURL)

	var authCode string
	if _, err := fmt.Scan(&authCode); err != nil {
		log.Fatalf("Unable to read authorization code: %v", err)
	}

	tok, err := config.Exchange(context.TODO(), authCode)
	if err != nil {
		log.Fatalf("Unable to retrieve token from web: %v", err)
	}
	return tok
}

// Retrieves a token from a local file.
func tokenFromFile(file string) (*oauth2.Token, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	tok := &oauth2.Token{}
	err = json.NewDecoder(f).Decode(tok)
	return tok, err
}

// Saves a token to a file path.
func saveToken(path string, token *oauth2.Token) {
	fmt.Printf("Saving credential file to: %s
", path)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		log.Fatalf("Unable to cache oauth token: %v", err)
	}
	defer f.Close()
	json.NewEncoder(f).Encode(token)
}

func randStr(strSize int, randType string) string {
	var dictionary string

	if randType == "alphanum" {
		dictionary = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	}

	if randType == "alpha" {
		dictionary = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	}

	if randType == "number" {
		dictionary = "0123456789"
	}

	var bytes = make([]byte, strSize)
	rand.Read(bytes)
	for k, v := range bytes {
		bytes[k] = dictionary[v%byte(len(dictionary))]
	}
	return string(bytes)
}

func main() {
	b, err := ioutil.ReadFile("credentials.json")
	if err != nil {
		log.Fatalf("Unable to read client secret file: %v", err)
	}

	// If modifying these scopes, delete your previously saved token.json.
	// Note that this scope will give the app full access to your account, so be careful (MailGoogleComScope)
	// If you don't want to delete mails, but only read and report (send), 
	// then you can use (gmail.GmailReadonlyScope, gmail.GmailComposeScope) instead of (MailGoogleComScope)
	// in that case comment lines from 178 to 181.
	config, err := google.ConfigFromJSON(b, gmail.MailGoogleComScope)
	if err != nil {
		log.Fatalf("Unable to parse client secret file to config: %v", err)
	}
	client := getClient(config)

	srv, err := gmail.New(client)
	if err != nil {
		log.Fatalf("Unable to retrieve Gmail client: %v", err)
	}

	pageToken := ""
	for {
		req := srv.Users.Messages.List("me").Q("in:spam")
		if pageToken != "" {
			req.PageToken(pageToken)
		}
		r, err := req.Do()
		if err != nil {
			log.Fatalf("Unable to retrieve messages: %v", err)
		}

		log.Printf("Processing %v messages...
", len(r.Messages))
		for _, m := range r.Messages {
			// We need to use Raw to be able to fetch the whole thing at once
			msg, err := srv.Users.Messages.Get("me", m.Id).Format("raw").Do()
			if err != nil {
				log.Fatalf("Unable to retrieve message %v: %v", m.Id, err)
			}

			// New message for our gmail service to send
			var message gmail.Message
			boundary := randStr(32, "alphanum")
			// It needs to be decoded from URL encoding otherwise strage things can happen
			body, err := base64.URLEncoding.DecodeString(msg.Raw)

			messageBody := []byte("Content-Type: multipart/mixed; boundary=" + boundary + " 
" +
				"MIME-Version: 1.0
" +
				"To: " + "submit.your_random_stuff@spam.spamcop.net" + "
" +
				"From: " + "kainlite@gmail.com" + "
" +
				"Subject: " + "Spam report" + "

" +

				"--" + boundary + "
" +
				"Content-Type: text/plain; charset=" + string('"') + "UTF-8" + string('"') + "
" +
				"MIME-Version: 1.0
" +
				"Content-Transfer-Encoding: 7bit

" +
				"Spam report" + "

" +
				"--" + boundary + "
" +

				"Content-Type: " + "message/rfc822" + "; name=" + string('"') + "email.txt" + string('"') + " 
" +
				"MIME-Version: 1.0
" +
				"Content-Transfer-Encoding: base64
" +
				"Content-Disposition: attachment; filename=" + string('"') + "email.txt" + string('"') + " 

" +
				string(body) +
				"--" + boundary + "--")

			// see https://godoc.org/google.golang.org/api/gmail/v1#Message on .Raw
			// use URLEncoding here !! StdEncoding will be rejected by Google API

			message.Raw = base64.URLEncoding.EncodeToString(messageBody)

			// Send the message
			_, err = srv.Users.Messages.Send("me", &message).Do()

			if err != nil {
				log.Printf("Error: %v", err)
			} else {
				fmt.Println("Message sent!")

				// If everything went well until here, then delete the message
				if err := srv.Users.Messages.Delete("me", m.Id).Do(); err != nil {
					log.Fatalf("unable to delete message %v: %v", m.Id, err)
				}
				log.Printf("Deleted message %v.
", m.Id)
			}
		}

		if r.NextPageToken == "" {
			break
		}
		pageToken = r.NextPageToken
	}
}

```
<br />

##### **Running it**
```elixir
$ spam
2019/12/31 17:45:14 Processing 2 messages...
Message sent!
Deleted message 1ac83e1f8.
Message sent!
Deleted message 2ac89cbd3.

```
<br />

##### **Sources**
Some articles, pages, and files that I used and helped me to do what I wanted to do:

- https://developers.google.com/gmail/api/quickstart/go
- https://github.com/gsuitedevs/go-samples/blob/master/gmail/quickstart/quickstart.go
- https://socketloop.com/tutorials/golang-send-email-with-attachment-rfc2822-using-gmail-api-example
- https://raw.githubusercontent.com/googleapis/google-api-go-client/master/examples/gmail.go
- https://github.com/xDinomode/Go-Gmail-Api-Example/blob/master/email.go
- https://www.spamcop.net/reporter.pl
- https://godoc.org/google.golang.org/api/gmail/v1#Message
<br />

### Additional notes
While this still needs some work hopefully will keep my account clean and probably help someone wondering about how to do the same.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Como reportar spam a spamcop desde GMail",
  author: "Gabriel Garrido",
  description: "Exploramos una pequeña herramienta para reportar correos basura a spamcop...",
  tags: ~w(golang linux),
  published: true,
  image: "spam.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![spam](/images/spam.png){:class="mx-auto"}

##### **Introducción**
Este post es un poco diferente a los demás, ya que es una pequeña "herramienta" que hice para facilitar el reporte de spam a [SpamCop.net](https://www.spamcop.net/). Esto ayuda a reducir el verdadero spam de fuentes desconocidas. Por alguna razón, empecé a recibir como 40 correos al día (todos iban a la carpeta de spam), pero igual resultaba molesto. Así que comencé a reportarlos a SpamCop, pero el proceso era algo lento y me cansé rápido, así que creé este "script" para hacer todo más fácil. Básicamente, lo que hace es listar todos los mensajes en la carpeta de spam, los descarga y luego los reenvía como adjuntos a SpamCop. Después de eso, recibís un mail con un enlace para confirmar el envío, ¡y listo!

Hay algunos pre-requisitos, como habilitar la API de GMail para tu cuenta. Podés hacerlo [aquí](https://developers.google.com/gmail/api/quickstart/go#step_1_turn_on_the). Después de eso, la primera vez que uses la app, tendrás que autorizarla. Esto lo hacés pegando la URL que la app te da en el navegador, luego haces clic en "Permitir", y después copiás el token que te da de vuelta en la terminal (solo se hace una vez). Después de eso, solo corrés el binario en un cronjob o tal vez como una lambda (aunque todavía no llegué a eso). Normalmente, reviso la carpeta de spam, elimino lo que no creo que sea spam o lo que sea, y luego corro el script para reportar todo lo que claramente es spam. Toma unos segundos, y luego recibo el enlace para confirmar todos los reportes (uno por uno, lamentablemente). Este script no es perfecto, ya que a veces SpamCop no puede leer correctamente el correo reenviado, pero he revisado exportándolos como archivo y los veo bien, así que será algo para investigar otro día. Este script lo hice en unas 2-4 horas, sin tener conocimientos previos de la API de GMail ni nada.

También necesitás configurar una cuenta de SpamCop, que vas a usar para enviar tus reportes. Podés hacerlo [aquí](https://www.spamcop.net/anonsignup.shtml).

El código fuente lo podés encontrar [aquí](https://github.com/kainlite/spamcop).
<br />

##### **Código**
He agregado algunos comentarios en el código para que sea más fácil de entender.
```elixir
package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"

	"golang.org/x/net/context"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/gmail/v1"
)

// Recupera un token, lo guarda y devuelve el cliente generado.
func getClient(config *oauth2.Config) *http.Client {
	// El archivo token.json almacena los tokens de acceso y actualización del usuario,
	// y se crea automáticamente cuando el flujo de autorización se completa por primera vez.
	tokFile := "token.json"
	tok, err := tokenFromFile(tokFile)
	if err != nil {
		tok = getTokenFromWeb(config)
		saveToken(tokFile, tok)
	}
	return config.Client(context.Background(), tok)
}

// Solicita un token desde la web, y luego devuelve el token recuperado.
func getTokenFromWeb(config *oauth2.Config) *oauth2.Token {
	authURL := config.AuthCodeURL("state-token", oauth2.AccessTypeOffline)
	fmt.Printf("Ve al siguiente enlace en tu navegador y luego ingresá el código de autorización: 
%v
", authURL)

	var authCode string
	if _, err := fmt.Scan(&authCode); err != nil {
		log.Fatalf("No se pudo leer el código de autorización: %v", err)
	}

	tok, err := config.Exchange(context.TODO(), authCode)
	if err != nil {
		log.Fatalf("No se pudo recuperar el token desde la web: %v", err)
	}
	return tok
}

// Recupera un token desde un archivo local.
func tokenFromFile(file string) (*oauth2.Token, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	tok := &oauth2.Token{}
	err = json.NewDecoder(f).Decode(tok)
	return tok, err
}

// Guarda un token en una ruta de archivo.
func saveToken(path string, token *oauth2.Token) {
	fmt.Printf("Guardando credenciales en el archivo: %s
", path)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		log.Fatalf("No se pudo guardar el token de oauth: %v", err)
	}
	defer f.Close()
	json.NewEncoder(f).Encode(token)
}

func randStr(strSize int, randType string) string {
	var dictionary string

	if randType == "alphanum" {
		dictionary = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	}

	if randType == "alpha" {
		dictionary = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	}

	if randType == "number" {
		dictionary = "0123456789"
	}

	var bytes = make([]byte, strSize)
	rand.Read(bytes)
	for k, v := range bytes {
		bytes[k] = dictionary[v%byte(len(dictionary))]
	}
	return string(bytes)
}

func main() {
	b, err := ioutil.ReadFile("credentials.json")
	if err != nil {
		log.Fatalf("No se pudo leer el archivo de credenciales del cliente: %v", err)
	}

	// Si modificás estos alcances, eliminá tu token.json guardado previamente.
	// Tené en cuenta que este alcance le dará a la app acceso completo a tu cuenta, así que tené cuidado (MailGoogleComScope).
	// Si no querés eliminar correos, pero solo leer y reportar (enviar),
	// entonces podés usar (gmail.GmailReadonlyScope, gmail.GmailComposeScope) en lugar de (MailGoogleComScope).
	// En ese caso, comentá las líneas desde la 178 hasta la 181.
	config, err := google.ConfigFromJSON(b, gmail.MailGoogleComScope)
	if err != nil {
		log.Fatalf("No se pudo analizar el archivo de credenciales del cliente: %v", err)
	}
	client := getClient(config)

	srv, err := gmail.New(client)
	if err != nil {
		log.Fatalf("No se pudo recuperar el cliente de Gmail: %v", err)
	}

	pageToken := ""
	for {
		req := srv.Users.Messages.List("me").Q("in:spam")
		if pageToken != "" {
			req.PageToken(pageToken)
		}
		r, err := req.Do()
		if err != nil {
			log.Fatalf("No se pudo recuperar los mensajes: %v", err)
		}

		log.Printf("Procesando %v mensajes...
", len(r.Messages))
		for _, m := range r.Messages {
			// Necesitamos usar Raw para poder obtener todo de una vez.
			msg, err := srv.Users.Messages.Get("me", m.Id).Format("raw").Do()
			if err != nil {
				log.Fatalf("No se pudo recuperar el mensaje %v: %v", m.Id, err)
			}

			// Nuevo mensaje para nuestro servicio de Gmail para enviar
			var message gmail.Message
			boundary := randStr(32, "alphanum")
			// Se debe decodificar de la codificación URL, de lo contrario pueden ocurrir cosas extrañas.
			body, err := base64.URLEncoding.DecodeString(msg.Raw)

			messageBody := []byte("Content-Type: multipart/mixed; boundary=" + boundary + " 
" +
				"MIME-Version: 1.0
" +
				"To: " + "submit.your_random_stuff@spam.spamcop.net" + "
" +
				"From: " + "kainlite@gmail.com" + "
" +
				"Subject: " + "Spam report" + "

" +

				"--" + boundary + "
" +
				"Content-Type: text/plain; charset=" + string('"') + "UTF-8" + string('"') + "
" +
				"MIME-Version: 1.0
" +
				"Content-Transfer-Encoding: 7bit

" +
				"Spam report" + "

" +
				"--" + boundary + "
" +

				"Content-Type: " + "message/rfc822" + "; name=" + string('"') + "email.txt" + string('"') + " 
" +
				"MIME-Version: 1.0
" +
				"Content-Transfer-Encoding: base64
" +
				"Content-Disposition: attachment; filename=" + string('"') + "email.txt" + string('"') + " 

" +
				string(body) +
				"--" + boundary + "--")

			// ver https://godoc.org/google.golang.org/api/gmail/v1#Message en .Raw
			// ¡Usá URLEncoding aquí! StdEncoding será rechazado por la API de Google

			message.Raw = base64.URLEncoding.EncodeToString(messageBody)

			// Envía el mensaje
			_, err = srv

.Users.Messages.Send("me", &message).Do()

			if err != nil {
				log.Printf("Error: %v", err)
			} else {
				fmt.Println("¡Mensaje enviado!")

				// Si todo salió bien hasta acá, entonces elimina el mensaje.
				if err := srv.Users.Messages.Delete("me", m.Id).Do(); err != nil {
					log.Fatalf("no se pudo eliminar el mensaje %v: %v", m.Id, err)
				}
				log.Printf("Mensaje eliminado %v.
", m.Id)
			}
		}

		if r.NextPageToken == "" {
			break
		}
		pageToken = r.NextPageToken
	}
}

```
<br />

##### **Ejecutándolo**
```elixir
$ spam
2019/12/31 17:45:14 Procesando 2 mensajes...
Mensaje enviado!
Mensaje eliminado 1ac83e1f8.
Mensaje enviado!
Mensaje eliminado 2ac89cbd3.

```
<br />

##### **Fuentes**
Algunos artículos, páginas y archivos que usé y me ayudaron a hacer lo que quería hacer:

- https://developers.google.com/gmail/api/quickstart/go
- https://github.com/gsuitedevs/go-samples/blob/master/gmail/quickstart/quickstart.go
- https://socketloop.com/tutorials/golang-send-email-with-attachment-rfc2822-using-gmail-api-example
- https://raw.githubusercontent.com/googleapis/google-api-go-client/master/examples/gmail.go
- https://github.com/xDinomode/Go-Gmail-Api-Example/blob/master/email.go
- https://www.spamcop.net/reporter.pl
- https://godoc.org/google.golang.org/api/gmail/v1#Message
<br />

### Notas adicionales
Aunque esto aún necesita algo de trabajo, espero que mantenga mi cuenta limpia y tal vez ayude a alguien que esté pensando en hacer lo mismo.
<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, por favor enviame un mensaje para que lo pueda corregir.

<br />
