Lemmy-Easy-Deploy
---

Deploy Lemmy the easy way!

Prerequisites & Quick Start
---

1. Make sure your server **has ports 80 and 443 available** (no webservers are already running).
	- Advanced users can define different ports to use.
2. Buy a domain name to use for Lemmy.
3. Set that domain's DNS records to point to your server's **public IP address**.
4. Install the ***official*** version of Docker to your server.
	- That means NOT using the version of Docker and Docker Compose supplied by your distribution (looking at you, Ubuntu!)
	- To ensure you have the ***official*** version of Docker, [follow the instructions for installing Docker and Docker Compose for your server distribution](https://docs.docker.com/engine/install/#server).
	- *You will probably need to reboot after installing.*

Once you've done all that, you're ready for the quickstart!

```
# Clone the repo
git clone https://github.com/ubergeek77/Lemmy-Easy-Deploy

# Change into the directory
cd ./Lemmy-Easy-Deploy

# Check out the latest tag
git checkout $(git describe --tags `git rev-list --tags --max-count=1`)

# Copy config.env.example to config.env
cp ./config.env.example ./config.env

# Make sure the DNS records for your domain point to your server
# Edit the config.env file, and at minimum, change LEMMY_HOSTNAME to be your domain. Then...

# Deploy!
./deploy.sh
```

The default deployment as outlined above will get you running in ***about 1 minute!***

See the **FAQ & Troubleshooting** section for answers to common questions, i.e. where your data is stored.

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

Over time, the recommended versions of `pictrs` and `postgres` may be updated by the Lemmy team. This script won't automatically pull those, and there isn't a great way to get those automatically. I will do my best to keep the template files in this repository up to date. When I have released new updates to Lemmy-Easy-Deploy, the script will print a notce reminding you to update. The script ***will not** update itself.*

CLI arguments and configuration:
---

```bash
Usage:
  ./deploy.sh [options]

Run with no options to check for Lemmy updates and deploy them

Options:
  -s|--shutdown          Shut down a running Lemmy-Easy-Deploy deployment (does not delete data)
  -l|--lemmy-tag <tag>   Install a specific version of the Lemmy Backend
  -w|--webui-tag <tag>   Install a specific version of the Lemmy WebUI (will use value from --lemmy-tag if missing)
  -f|--force-deploy      Skip the update checker and force (re)deploy the latest/specified version
  -r|--rebuild           Deploy from source, don't update the Git repos, and deploy them as-is, implies -f and ignores -l/-w
  -y|--yes               Answer Yes to any prompts asking for confirmation
  -v|--version           Prints the current version of Lemmy-Easy-Deploy
  -u|--update            Update Lemmy-Easy-Deploy
  -d|--diag              Dump diagnostic information for issue reporting, then exit
  -h|--help              Show this help message
```

*Tip: If you have edited your `config.env` and want to re-deploy your changes, but no updates are available, use `./deploy.sh -f`!*

There are some additional configuration options available in `config.env`. See that file for more details. You can configure things such as:

- Your Lemmy hostname
- A Cloudflare API key to use DNS HTTPS certificate generation (works better for Cloudflare Proxy users)
- Build Lemmy from source instead of pulling the Docker Hub image
- ...and even more options for advanced users! See the comments in `config.env` for more details!


FAQ & Troubleshooting
---
- Where is my password?
	- On your ***first*** deployment, these credentials will also be printed to the console.
	- If you need them again, check `./live/lemmy.hjson` for your first time setup credentials, or run:

	```bash
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	```

- I can't reach my Lemmy instance and/or HTTPS isn't working!
	- Make sure your firewall isn't blocking ports 80 and 443. On most server distributions, `ufw` blocks this by default, so check your `ufw` settings
	- **If you're using Cloudflare's proxy,** specify an API token in `config.env`, **and change Cloudflare's SSL mode to Full (Strict)**.

- I get a "too many redirects" error!
	- Are you using the Cloudflare proxy? If yes, try entering your Cloudflare API token in `config.env`, changing the SSL/TLS mode to "Full (Strict)" in Cloudflare, then redeploy by running `./deploy.sh -f`

- I can't sign up for my instance!
	- Check the Lemmy docs for a guide on first-time setup: https://join-lemmy.org/docs/en/administration/first_steps.html

- I got some kind of `sed` error.
	- Did you use special characters in any of the `config.env` options, such as a `|`? You will need to backslash escape it. Put `\` in front of any special characters, then try again. For example:
	```bash
	SETUP_SITE_NAME="Lemmy \| MyServer"
	```

- Where is all my data?
	- Deployment files and generated secrets are in `./live`. Don't delete them!
	- This script deploys a Lemmy instance using Docker compose, with a **stack name** of `lemmy-easy-deploy`.
	- This is all Docker under the hood, so you can find your Lemmy-specific data (such as the database) stored in Docker volumes. List them with
	```bash
	docker volume ls
	```

- How can I run regular `docker compose` commands?
  - This script deploys a Lemmy instance using Docker compose, with a **stack name** of `lemmy-easy-deploy`
  - Therefore, you will have to `cd ./live`, then run:
  ```bash
  docker compose -p lemmy-easy-deploy <command>
  ```
  - `<command>` can be whatever Docker Compose supports, up,down,ps, etc.

- How can I check the logs?
	- You can use this command to see a live feed of logs `docker compose -p lemmy-easy-deploy logs -f`
	- By default, each service will log up to 500MB of data, removing old log messages if this cap is reached.
	- To find your log files and find out which ones are taking up space, use:
	```bash
	du -h $(docker inspect --format='{{.LogPath}}' $(docker ps -qa))
	```

- I have some special use case involving a separate webserver and reverse proxies.
	- Sorry, but as that kind of configuration can vary significantly, this is not a use case I can support. Lemmy-Easy-Deploy is intended for users new to hosting and do not have any webservers set up at all.
	- However, I do provide you with some options in `config.env` that may help you configure Lemmy-Easy-Deploy to work with this kind of setup. Hopefully those options will be of use to you!

Credits
---

- The Lemmy project maintainers, for making Lemmy: https://github.com/LemmyNet/lemmy
- [@QPixel](https://github.com/QPixel), for helping me QA test this


Support me
---

I ***am not*** a maintainer or contributor to the Lemmy project. Lemmy does not belong to me and I did not make it. But, if my script helped you, and you would like to support me, I have crypto addresses:

- Bitcoin: `bc1qekqn4ek0dkuzp8mau3z5h2y3mz64tj22tuqycg`
- Monero/Ethereum: `0xdAe4F90E4350bcDf5945e6Fe5ceFE4772c3B9c9e`

