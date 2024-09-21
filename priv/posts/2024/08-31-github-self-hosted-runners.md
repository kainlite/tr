%{
  title: "Did you know that you can have up to 10000 Github self-hosted runners?",
  author: "Gabriel Garrido",
  description: "In this article we will quickly explore how easy it is to configure a new runner, to build or automate
  any task within github actions",
  tags: ~w(git github tips-and-tricks),
  published: true,
  image: "github-logo.png",
  sponsored: false,
  video: "https://youtu.be/sDjXY5RJX3c",
  lang: "en"
}
---

### **Introduction**
<br />

Did you know that you can have up to 10000 Github self-hosted runners?
Yes you read that correctly, that means you can control your costs, how you organize and manage your CI infrastructure,
by default at this time, GitHub usage limits are pretty high for self-hosted runners, you can read more [here](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#usage-limits).
<br />

This might change, so refer to their docs for an updated version but as of now:
* Job execution time - Each job in a workflow can run for up to 5 days of execution time. If a job reaches this limit, the job is terminated and fails to complete.
* Workflow run time - Each workflow run is limited to 35 days. If a workflow run reaches this limit, the workflow run is cancelled. This period includes execution duration, and time spent on waiting and approval.
* Job queue time - Each job for self-hosted runners that has been queued for at least 24 hours will be canceled. The actual time in queue can reach up to 48 hours before cancellation occurs. If a self-hosted runner does not start executing the job within this limit, the job is terminated and fails to complete.
* API requests - You can execute up to 1,000 requests to the GitHub API in an hour across all actions within a repository. If requests are exceeded, additional API calls will fail which might cause jobs to fail.
* Job matrix - A job matrix can generate a maximum of 256 jobs per workflow run. This limit applies to both GitHub-hosted and self-hosted runners.
* Workflow run queue - No more than 500 workflow runs can be queued in a 10 second interval per repository. If a workflow run reaches this limit, the workflow run is terminated and fails to complete.
* Registering self-hosted runners - You can have a maximum of 10,000 self-hosted runners in one runner group. If this limit is reached, adding a new runner will not be possible.

<br />
You can add a self-hosted runner to a repository, an organization, or an enterprise. 
<br />

### **Why do I need self-hosted runners?**

Let's say you need to build and run software on Linux ARM64, there are no GitHub-hosted runners for that Operative
system and architecture yet.
<br />

At the same time you get full control of your runner, this can be tricky in public repositories where someone could send
a Pull Requests to leak information about your infrastructure, or run some dangerous package, etc, if you are going to
be using this publicly you should spend some time hardening the setup to avoid bad actors, however there are several
alternatives that can work fine.

<br />
Some interesting terraform modules and alternatives:
* https://philips-labs.github.io/terraform-aws-github-runner
* https://github.com/cloudandthings/terraform-aws-github-runners

### **How can I get started with self-hosted runners?**

That's pretty straight-forward, if you are only going to use it from a specific repository you can add it from the
repository settings, here is an example, go to your repository, then actions, then runners, hit the green button to add
a new runner, it should look something like this 👇.

![img1](/images/github-selfhosted-1.png){:class="mx-auto"}

The next step would be to configure it in your node, this of course is not the most reliable way to configure your
runners specially when you need to consider auto-scaling or zero-scaling, or ephemeral runners, however to test things
out or get started is enough.

![img1](/images/github-selfhosted-console-1.png){:class="mx-auto"}

If everything was done correctly, then you should see your node listed in there:
![img1](/images/github-selfhosted-2.png){:class="mx-auto"}

To remove the node just execute the script again as shown in the image.
![img1](/images/github-selfhosted-3.png){:class="mx-auto"}

And that's it, remember be very security concious and heavily restrict the actions that can be performed on your
repository if it is a public repo.

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
---lang---
%{
  title: "Did you know that you can have up to 10000 Github self-hosted runners?",
  author: "Gabriel Garrido",
  description: "In this article we will quickly explore how easy it is to configure a new runner, to build or automate
  any task within github actions",
  tags: ~w(git github tips-and-tricks),
  published: true,
  image: "github-logo.png",
  sponsored: false,
  video: "https://youtu.be/sDjXY5RJX3c",
  lang: "es"
}
---

### Traduccion en proceso

### **Introduction**
<br />

Did you know that you can have up to 10000 Github self-hosted runners?
Yes you read that correctly, that means you can control your costs, how you organize and manage your CI infrastructure,
by default at this time, GitHub usage limits are pretty high for self-hosted runners, you can read more [here](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#usage-limits).
<br />

This might change, so refer to their docs for an updated version but as of now:
* Job execution time - Each job in a workflow can run for up to 5 days of execution time. If a job reaches this limit, the job is terminated and fails to complete.
* Workflow run time - Each workflow run is limited to 35 days. If a workflow run reaches this limit, the workflow run is cancelled. This period includes execution duration, and time spent on waiting and approval.
* Job queue time - Each job for self-hosted runners that has been queued for at least 24 hours will be canceled. The actual time in queue can reach up to 48 hours before cancellation occurs. If a self-hosted runner does not start executing the job within this limit, the job is terminated and fails to complete.
* API requests - You can execute up to 1,000 requests to the GitHub API in an hour across all actions within a repository. If requests are exceeded, additional API calls will fail which might cause jobs to fail.
* Job matrix - A job matrix can generate a maximum of 256 jobs per workflow run. This limit applies to both GitHub-hosted and self-hosted runners.
* Workflow run queue - No more than 500 workflow runs can be queued in a 10 second interval per repository. If a workflow run reaches this limit, the workflow run is terminated and fails to complete.
* Registering self-hosted runners - You can have a maximum of 10,000 self-hosted runners in one runner group. If this limit is reached, adding a new runner will not be possible.

<br />
You can add a self-hosted runner to a repository, an organization, or an enterprise. 
<br />

### **Why do I need self-hosted runners?**

Let's say you need to build and run software on Linux ARM64, there are no GitHub-hosted runners for that Operative
system and architecture yet.
<br />

At the same time you get full control of your runner, this can be tricky in public repositories where someone could send
a Pull Requests to leak information about your infrastructure, or run some dangerous package, etc, if you are going to
be using this publicly you should spend some time hardening the setup to avoid bad actors, however there are several
alternatives that can work fine.

<br />
Some interesting terraform modules and alternatives:
* https://philips-labs.github.io/terraform-aws-github-runner
* https://github.com/cloudandthings/terraform-aws-github-runners

### **How can I get started with self-hosted runners?**

That's pretty straight-forward, if you are only going to use it from a specific repository you can add it from the
repository settings, here is an example, go to your repository, then actions, then runners, hit the green button to add
a new runner, it should look something like this 👇.

![img1](/images/github-selfhosted-1.png){:class="mx-auto"}

The next step would be to configure it in your node, this of course is not the most reliable way to configure your
runners specially when you need to consider auto-scaling or zero-scaling, or ephemeral runners, however to test things
out or get started is enough.

![img1](/images/github-selfhosted-console-1.png){:class="mx-auto"}

If everything was done correctly, then you should see your node listed in there:
![img1](/images/github-selfhosted-2.png){:class="mx-auto"}

To remove the node just execute the script again as shown in the image.
![img1](/images/github-selfhosted-3.png){:class="mx-auto"}

And that's it, remember be very security concious and heavily restrict the actions that can be performed on your
repository if it is a public repo.

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />
