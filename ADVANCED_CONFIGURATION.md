Advanced Configuration
---

***NOTE:*** The customization features of Lemmy-Easy-Deploy **are provided for convenience and are not supported**. In other words, these are for advanced users only, and have great potential to break your deployment if you don't know what you're doing. ***I can't help you with issues related to these customization options, do not use them if you do not know what you are doing***. Please, do not file issues related to using these features (unless something is obviously broken).

In order for any of the below configuration options to be used/executed, a redeployment must occur. A redeployment will happen automatically upon updates with `./deploy.sh`, but if no updates are available, you must use `./deploy.sh -f` to redeploy them (don't forget to use `-l` or `-w` if you want to maintain a custom `rc` version, or the latest stable version will be deployed instead).

### Custom Environment Variables

If you need to specify a certain environment variable for a given service in this deployment, you can define them in any of the below files. If one of those files exist, they will be passed to each respective service as an `env_file`. This allows you to specify any environment variables you want for any service. These files follow the [Docker environment file syntax](https://docs.docker.com/compose/environment-variables/env-file/) (basically just `VAR=VAL`).

```
# Will be loaded by the 'proxy` service (Caddy)
./custom/customCaddy.env

# Will be loaded by the 'lemmy' service
./custom/customLemmy.env

# Will be loaded by the 'lemmy-ui' service
./custom/customLemmy-ui.env

# Will be loaded by the 'pictrs' service
./custom/customPictrs.env

# Will be loaded by the 'postgres' service
./custom/customPostgres.env

# Will be loaded by the 'postfix' service
./custom/customPostfix.env
```

### Template overriding

Lemmy-Easy-Deploy makes use of *templates* to generate the files necessary for a successful deployment. Some users may need to customize these templates, such as if they want to add a service to `docker-compose.yml`, change network settings, or anything of the sort.

The names are self-explanatory. If any of these files exist, that respective file will be used instead of the default template:

```
./custom/Caddy-Dockerfile.template
./custom/Caddyfile.template
./custom/cloudflare.snip
./custom/compose-email.snip
./custom/compose-email-volumes.snip
./custom/docker-compose.yml.template
./custom/lemmy-email.snip
./custom/lemmy.hjson.template
```

***NOTE:*** Over time, the default templates may need to be updated as new versions of Lemmy come out. For example, the `pictrs` version may be updated, new environment variables specified, or API routes shifted. If you use a custom template, you will not automatically receive updates to these things, as your deployment will use your static template instead of my default ones. **You are responsible for keeping your custom template up to date.**

### Pre/Post Deployment Scripts

Lemmy-Easy-Deploy can run pre and post-deployment scripts for you if you have them written to:

```
./custom/pre-deploy.sh
./custom/post-deploy.sh
```

They will be executed just before the Docker Compose deployment is brought up, and right after it's brought up, respectively.

These can be useful to do things such as:

- Create/Generate files and copy them to `./live`
- Programatically modify files in `./live` right before a deployment
- Manually execute into running services to run commands

This is a powerful feature, but please be careful when using it. It is your responsibility to not break your deployment if you use this feature.