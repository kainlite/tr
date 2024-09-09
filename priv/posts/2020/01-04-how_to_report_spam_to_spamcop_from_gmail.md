%{
  title: "How to report spam to spamcop from gmail",
  author: "Gabriel Garrido",
  description: "Easy method to report spam to spamcop using GMail, this helps to reduce the true Spam from unknown sources, since for some reason I started to get...",
  tags: ~w(linux),
  published: true,
  image: "spam.png",
  sponsored: false,
  video: ""
}
---

![spam](/images/spam.png){:class="mx-auto"}

##### **Introduction**
Easy method to report spam to [SpamCop.net](https://www.spamcop.net/) using GMail, this helps to reduce the true Spam from unknown sources, since for some reason I started to get like 40 emails per day (all went to spam), but it is still somewhat annoying, so I started reporting it to spamcop, this alternative method doesn't need a script and it's really easy to do as well, same result as with the script from [the previous post](https://techsquad.rocks/blog/how_to_report_your_gmail_spam_folder_to_spamcop/).

Pre-requisites:

* GMail account
* Setup a spamcop account which you will be using to send your reports, you can do that [here](https://www.spamcop.net/anonsignup.shtml)
<br />

##### **Forwarding as attachment**
First of all you need to select all emails and then click on the three dots and select "Forward as attachment"
![img](/images/spamcop-1.png){:class="mx-auto"}
<br />

##### **Sending it to your spamcop email**
In this step the only thing that you need to do is put your Spamcop email (it gives you this address to report spam when you create the account and in the report spam tab), you do not need to put anything in the body or the subject, just send it as is.
![img](/images/spamcop-2.png){:class="mx-auto"}
<br />

##### **Confirming each one**
Then you will get an email with a link to each spam message to submit the report.
![img](/images/spamcop-3.png){:class="mx-auto"}
<br />

##### **Sending the reports**
This is a sample report, you can add additional notes if needed and then confirm to send it to the abuse addresses of the owners of the IPs and links found in the email.
![img](/images/spamcop-4.png){:class="mx-auto"}
<br />

### Additional notes
This method is pretty easy for someone who doesn't want to run a script or whatever and is still able to report the spam to the sources, however if you want something a bit less manual you can try with the script or just create a filter to delete everything in the spam folder.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
