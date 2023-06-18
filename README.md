Lemmy-Easy-Deploy
---

Deploy Lemmy the easy way!

Quick Start
---

Make sure you have a server **that has ports 80 and 443 available,** and has already pointed a domain you control to your server's IP address.

***Running Lemmy-Easy-Deploy behind a separate webserver or reverse proxy is not supported.*** I've given you config options that may help you run it anyway (control of the ports, disable HTTPS in case it's externally managed), but if this is your use case, you are on your own. Sorry about that!

Before running the commands, make sure you have Docker installed. [Follow the instructions for installing Docker and Docker Compose for your server distribution](https://docs.docker.com/engine/install/#server). Then:

```
# Clone the repo
git clone https://github.com/ubergeek77/Lemmy-Easy-Deploy

# Change into the directory
cd ./Lemmy-Easy-Deploy

# Copy config.env.example to config.env
cp ./config.env.example ./config.env

# Make sure the DNS records for your domain point to your server
# Edit the config.env file, and at minimum, change LEMMY_HOSTNAME to be your domain. Then...

# Deploy!
./deploy.sh
```

The default deployment as outlined above will get you running in ***about 1 minute!***

*NOTE: on non x86_64 platforms, such as ARM, **Lemmy-Easy-Deploy will have to compile Lemmy from source,** as ARM-based Docker Hub images are not always available for the latest Lemmy version. This will increase deploy time to about 20-30 minutes while Lemmy compiles*

What is this?
---
This repo provides an "out of the box" installer for Lemmy that sets up everything for you automatically. Unlike the Ansible installer, this does not require a Debian-based distribution, and can be run on pretty much any system with Docker installed.

Features:

- Near-zero config, run the script once and deploy
- Re-run the script to detect Lemmy updates and automatically deploy them
- Automatic and hands-off HTTPS certificate management

The script generates all the deployment files necessary to deploy Lemmy based on your configuration in `config.env`. Passwords for Lemmy's internal microservices will be generated randomly as needed.

**All deployment files will be placed in the `./live` directory relative to `deploy.sh`**

*NOTE: It is not recommended to edit any of the files in `./live` directly! Changes may not take effect like you might expect, and they will be replaced on each redeployment. If you need to customize your deployment, advanced users can edit the files in `./templates` accordingly*

Updates
---

If Lemmy releases a new update, simply run `./deploy.sh` again to deploy it. The script will automatically fetch the latest release and update your deployment. If a version of Lemmy you want to run has not been tagged yet, see below for how to specify versions.

Over time, the recommended versions of `pictrs` and `postgres` may be updated by the Lemmy team. This script won't automatically pull those, and there isn't a great way to get those automatically. I will do my best to keep the template files in this repository up to date. If they change, you can check those files as a reference, or run `git pull` in `Lemmy-Easy-Deploy` to update them.

CLI arguments and configuration:
---

```bash
Usage:
  ./deploy.sh [-u|--update-version <version>] [-f|--force-deploy] [-h|--help]

Options:
  -u|--update-version <version>   Override the update checker and update to <version> instead.
  -f|--force-deploy               Skip the update checker and force (re)deploy the latest/specified version.
  -h|--help                       Show this help message.
```

*Tip: If you have edited your `config.env` and want to re-deploy your changes, but no updates are available, use `./deploy.sh -f`!*

There are some additional configuration options available in `config.env`. See that file for more details. You can configure things such as:

- Your Lemmy hostname
- A Cloudflare API key to use DNS HTTPS certificate generation (works better for Cloudflare Proxy users)
- Build Lemmy from source instead of pulling the Docker Hub image
- ...and even more options for advanced users! See the comments in `config.env` for more details!


FAQ & Troubleshooting:
---
- I got some kind of `sed` error.
	- Did you use special characters in any of the `config.env` options, such as a `|`? You will need to backslash escape it. Put `\` in front of any special characters, then try again. For example:
	```bash
	SETUP_SITE_NAME="Lemmy \| MyServer"
	```

- Where is all my data?
	- This script deploys a Lemmy instance using Docker compose, with a **stack name** of `lemmy-easy-deploy`.
	- This is all Docker under the hood, so you can find your data stored in Docker volumes. List them with
	```bash
	docker volume ls
	```

- How can I check the logs?
	- You can use this command to see a live feed of logs `docker compose -p lemmy-easy-deploy logs -f`
	- By default, each service will log up to 500MB of data, removing old log messages if this cap is reached.
	- To find your log files and find out which ones are taking up space, use:
	```bash
	du -h $(docker inspect --format='{{.LogPath}}' $(docker ps -qa))
	```

- How can I run regular `docker compose` commands?
  - This script deploys a Lemmy instance using Docker compose, with a **stack name** of `lemmy-easy-deploy`
  - Therefore, you will have to `cd ./live`, then run:
  ```bash
  docker compose -p lemmy-easy-deploy <command>
  ```
  - `<command>` can be whatever Docker Compose supports, up,down,ps, etc.

- I have some special use case involving a separate webserver and reverse proxies.
	- Sorry, but as that kind of configuration can vary significantly, this is not a use case I can support. Lemmy-Easy-Deploy is intended for users new to hosting and do not have any webservers set up at all.
	- However, I do provide you with some options in `config.env` that may help you configure Lemmy-Easy-Deploy to work with this kind of setup. Hopefully those options will be of use to you!

- I can't reach my Lemmy instance and/or HTTPS isn't working!
	- Make sure your firewall isn't blocking ports 80 and 443. On most server distributions, `ufw` blocks this by default, so check your `ufw` settings
	- If you're using Cloudflare's proxy, specify an API token in `config.env`. This will switch to DNS certificate generation which should avoid any HTTPS issues.

- I get a "too many redirects" error!
	- Are you using the Cloudflare proxy? If yes, try entering your Cloudflare API token in `config.env`, changing the SSL/TLS mode to "Full (Strict)" in Cloudflare, then redeploy by running `./deploy.sh -f`

- I can't sign up for my instance!
	- Check the Lemmy docs for a guide on first-time setup: https://join-lemmy.org/docs/en/administration/first_steps.html

- Where is my password?
	- On your ***first*** deployment, these credentials will also be printed to the console.
	- If you need them again, check `./live/lemmy.hjson` for your first time setup credentials, or run:

	```bash
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	```

Credits:
---

- The Lemmy project maintainers, for making Lemmy: https://github.com/LemmyNet/lemmy
- [@QPixel](https://github.com/QPixel), for helping me QA test this
