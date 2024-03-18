%{
  title: "How to report your gmail spam folder to spamcop",
  author: "Gabriel Garrido",
  description: "This post is a bit different from the others in the sense that it's a small tool I did to ease spam reporting to...",
  tags: ~w(golang linux),
  published: true,
}
---

![spam](/images/spam.jpg){:class="mx-auto"}

##### **Introduction**
This post is a bit different from the others in the sense that it's a small "tool" I did to ease spam reporting to [SpamCop.net](https://www.spamcop.net/), this helps to reduce the true Spam from unknown sources, since for some reason I started to get like 40 emails per day (all went to spam), but it is still somewhat annoying, so I started reporting it to spamcop, but the process was kind of slow and I got tired of that quickly, so I created this "script" to make things easier. Basically what it does is list all messages in the spam folders fetches them and then forwards each one as an attachment to spamcop, then you get an email with a link to confirm the submission and that's it.

There are a few pre-requisites, like enabling the GMail API for your account, you can do that [here](https://developers.google.com/gmail/api/quickstart/go#step_1_turn_on_the), after that the first time you use the app you have to authorize it, you do this by pasting the URL that the app gives you in the browser, then clicking Allow, and then pasting the token that it gives you back in the terminal (this only needs to be done once), after that you just run the binary in a cronjob or maybe even as a lambda (but I haven't gone there yet), I usually check the spam folder remove what I don't think it's spam or whatever and then run the script to report everything else that it is clearly spam, it takes a few seconds and then I get the link to confirm all reports (one by one, sadly), this script is not perfect as sometimes spamcop cannot read properly the forwarded email, but I have checked exporting those as a file and I do see them all right, so that will be an investigation for another day, this only took like 2-4 hours, having 0 knowledge of the GMail API, etc.

Also you need to setup a spamcop account which you will be using to send your reports, you can do that [here](https://www.spamcop.net/anonsignup.shtml)

The source code can be found [here](https://github.com/kainlite/spamcop)

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

##### **Running it**
```elixir
$ spam
2019/12/31 17:45:14 Processing 2 messages...
Message sent!
Deleted message 1ac83e1f8.
Message sent!
Deleted message 2ac89cbd3.

```

##### **Sources**
Some articles, pages, and files that I used and helped me to do what I wanted to do:

- https://developers.google.com/gmail/api/quickstart/go
- https://github.com/gsuitedevs/go-samples/blob/master/gmail/quickstart/quickstart.go
- https://socketloop.com/tutorials/golang-send-email-with-attachment-rfc2822-using-gmail-api-example
- https://raw.githubusercontent.com/googleapis/google-api-go-client/master/examples/gmail.go
- https://github.com/xDinomode/Go-Gmail-Api-Example/blob/master/email.go
- https://www.spamcop.net/reporter.pl
- https://godoc.org/google.golang.org/api/gmail/v1#Message

### Additional notes
While this still needs some work hopefully will keep my account clean and probably help someone wondering about how to do the same.

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)
