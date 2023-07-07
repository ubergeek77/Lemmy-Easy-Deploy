FAQ & Troubleshooting
---

- Where is my password?
	- On your ***first*** deployment, these credentials will also be printed to the console.
	- If you need them again, check `./live/lemmy.hjson` for your first time setup credentials, or run:

	```bash
	cat ./live/lemmy.hjson | grep -e "admin_.*:"
	```

- How do I specify a custom Postgres config to optimize my Postgres database?
	- Create a the directory `./custom`, and place your custom Postgres config at `./custom/customPostgresql.conf`
	- Please see the [Usage & Configuration section of the README](https://github.com/ubergeek77/Lemmy-Easy-Deploy/edit/main/README.md#usage--configuration) for more info.

- I want to change an environment variable that's not in `config.env` and not in `docker-compose.yml`. What should I do?
	- Create a the directory `./custom`, and place your custom environment variable in the appropriately named file.
	 - Please see the [Usage & Configuration section of the README](https://github.com/ubergeek77/Lemmy-Easy-Deploy/edit/main/README.md#usage--configuration) for more info.

- I can't reach my Lemmy instance and/or HTTPS isn't working!
	- Make sure your firewall isn't blocking ports 80 and 443. On most server distributions, `ufw` blocks this by default, so check your `ufw` settings
	- **If you're using Cloudflare's proxy,** specify an API token in `config.env`, **and change Cloudflare's SSL mode to Full (Strict)**.
	- If you are using **Cloudflared**, try setting `CADDY_DISABLE_TLS` to `true`, and pointing **Cloudflared** to `localhost:80`
	- Test your instance on your server with these commands:
		- HTTPS: `curl --resolve your-lemmy-domain.com:443:127.0.0.1 https://your-lemmy-domain.com/api/v3/community/list`
		- HTTP: `curl --resolve your-lemmy-domain.com:80:127.0.0.1 http://your-lemmy-domain.com/api/v3/community/list`
	- If you see a JSON response from your Lemmy instance, then the deployment is working, and you likely have a firewall issue

- I get a "too many redirects" error!
	- Are you using the Cloudflare proxy? If yes, try entering your Cloudflare API token in `config.env`, changing the SSL/TLS mode to "Full (Strict)" in Cloudflare, then redeploy by running `./deploy.sh -f`

- I can't sign up on my instance!
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

- How do I migrate my Lemmy instance into or out of Lemmy-Easy-Deploy, or make backups of my volumes?
	- I do not currently have an automatic system for migrating or managing backups.
	- However, the data under the hood is just stored in Docker volumes.
	- Please see the official Docker documentation for information on how to get data into and out of Docker volumes:
		- https://docs.docker.com/storage/volumes/#back-up-restore-or-migrate-data-volumes

- How can I run regular `docker compose` commands?
  - This script deploys a Lemmy instance using Docker compose, with a **stack name** of `lemmy-easy-deploy`
  - Therefore, you will have to `cd ./live`, then run:
  ```bash
  docker compose -p lemmy-easy-deploy <command>
  ```
  - `<command>` can be whatever Docker Compose supports, up,down,ps, etc.
  - Support will not be given for this use case.

- How can I check the logs?
	- You can use this command to see a live feed of logs `docker compose -p lemmy-easy-deploy logs -f`
	- By default, each service will log up to 500MB of data, removing old log messages if this cap is reached.
	- To find your log files and find out which ones are taking up space, use:
	```bash
	du -h $(docker inspect --format='{{.LogPath}}' $(docker ps -qa))
	```

- I have some special use case involving a separate webserver and reverse proxies.
	- Sorry, but as that kind of configuration can vary significantly, this is not a use case I can support. Lemmy-Easy-Deploy is intended for users new to hosting and do not have any webservers set up at all.
	- However, I do provide you with plenty of options in `config.env` that may help you configure Lemmy-Easy-Deploy to work with this kind of setup. Hopefully those options will be of use to you!
