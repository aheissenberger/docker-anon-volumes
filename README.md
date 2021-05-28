# Docker compose up build fails to update container

if you try the following command to **update your service after changes** and it works for you with some project but **not with all project** I can help you to fix the problem and understand the reason behind this behaviour:

```bash
docker compose -f docker-compose.prod.yml up --build --no-deps --detach your_service
```

Let's explain what this command is requested to do:
* `up` start the service `your_service`
* `--build` build the image if it does not exist or has changed. Use cache for parts which have not changed.
* `--no-deps` do not start any linked services
* `--detach` run container in background
_(official documentation [docker-compose up](https://docs.docker.com/compose/reference/up/))_

What we expect after we changed files which are part of the image:
* rebuild of the image
* using the cache to avoid rebuild of parts which have not changed
* restart of the container based on the new image

There are many places on the web which suggest this command and for it only worked with some of my projects. Digging into the problem I found out that the reason behind are **anonymous volumes**.

## Solution

To fix the problem with **anonymous volumes** you only need to add `--renew-anon-volumes`:
```bash
docker compose -f docker-compose.prod.yml up --build --no-deps --renew-anon-volumes --detach your_service
```
The additional flag will allway recreate all anonymous volumes on the restart for this service. This will make any changes overlapping with these volumes to become visible.

## What's behind anonymous volumes

### Check for existing anon volumes

Use this command and replace `<your container id>` with your container ID:
```bash
docker inspect --type container -f '{{range $i, $v := .Mounts }}{{printf "%v\n" $v}}{{end}}' <your container id>
```
all anonymous volumes will have a long internal hash directly after `{volume `:
```
{volume 277654df19e38eeb10f92be90c8df76558033bcd3c7b871e75abdc14174a46d8 /var/lib/docker/volumes/277654df19e38eeb10f92be90c8df76558033bcd3c7b871e75abdc14174a46d8/_data /opt/app/etc local  true }
```

### How do I create such a volume?

**A) docker-compose.yml**

```yml
services:
  your_service:
     build: .
     volumes:
       - /my_data # anonymous volume
```

**B) Dockerfile**

```docker
VOLUME  "/var/logs" "/data"
```

Let's asume that we normally only use named volumes and no  anonymous volumes in our `docker-compose.yml` files and focus on option B).

If we look at the official  documentation for [VOLUME](https://docs.docker.com/engine/reference/builder/#volume) we will not find any clues:
> The`VOLUME`instruction creates a mount point with the specified name and marks it as holding externally mounted volumes from native host or other containers. The…

To explain the details we need an example which simulates the problem.

```
src
  config
    name.txt
  hello-world.sh
  Dockerfile
docker-compose.yml
```

**src/hello-world.sh** - our service app
```bash
#!/bin/sh
NAME=$(cat /app/config/name.txt)
while sleep 5; do  echo  "Hello World! Hello $NAME"; done
```

**src/config/name.txt** - a config file
```
Max
```

**src/Dockerfile** 
```docker
FROM  alpine
COPY  hello-world.sh  /app/hello-world.sh
COPY  config/name.txt  /app/config/name.txt
CMD  \["sh","/app/hello-world.sh"\]
```

**docker-compose.yml** 
```yaml
services:
  hello:
    build: ./src
```

we can start the service:
`docker compose up --detach`
_**Hint:** if you do not have the latest version of docker, you will have to replace `docker compose` with `docker-compose` with the dash between the words!_

```
Creating network "docker-anon-volumes_default" with the default driver
Building hello
[+] Building 2.0s (8/8) FINISHED                                                           
Use 'docker scan' to run Snyk tests against images to find vulnerabilities and learn how to fix them
WARNING: Image for service hello was built because it did not already exist. To rebuild this image you must use `docker-compose build` or `docker-compose up --build`.
Creating docker-anon-volumes_hello_1 ... done
Attaching to docker-anon-volumes_hello_1
hello_1  | Hello World! Hello Max
hello_1  | Hello World! Hello Max
```

check the output of the service:
```bash
$ docker compose logs -f
hello_1  | Hello World! Hello Max
hello_1  | Hello World! Hello Max
hello_1  | Hello World! Hello Max
...
```

now we change the content in file `src/config/name.txt` from `Max` to `Rudi`
`echo "Rudi">src/config/name.txt` 
and restart the service with the new configuration
`docker compose up --build --no-deps --detach` 

check the output of the service:
```bash
$ docker compose logs -f
hello_1  | Hello World! Hello Rudi
hello_1  | Hello World! Hello Rudi
...
```
Exactly what we expected.

Check for anonymous volumes:
1. get the ID of the container
    ```bash
    $ docker ps        
    CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS          PORTS     NAMES
    1df0f6ee87d4   1c356deb72b1   "sh /app/hello-world…"   40 seconds ago   Up 37 seconds             docker-anon-volumes_hello_1
  ```
 2. run the command to list the volumes with your container id `1df0f6ee87d4` from `docker ps`
    ```bash
  $ docker inspect --type container -f '{{range $i, $v := .Mounts }}{{printf "%v\n" $v}}{{end}}' 1df0f6ee87d4
  ```

**There should be no output by this command!**

Now we change our `Dockerfile` to **optional** allow to bind the `app/config` directory to a local directory for development by adding the `VOLUME` command.

**src/Dockerfile** 
```docker
FROM  alpine
COPY  hello-world.sh  /app/hello-world.sh
COPY  config/name.txt  /app/config/name.txt
VOLUME /app/config
CMD  \["sh","/app/hello-world.sh"\]
```

restart the service with the new configuration
`docker compose up --build --no-deps --detach` 

check the output of the service:
```bash
$ docker compose logs -f
hello_1  | Hello World! Hello Rudi
hello_1  | Hello World! Hello Rudi
...
```
now we change the content in file `src/config/name.txt` from `Rudi` to `Franz`
`echo "Franz">src/config/name.txt` 

restart the service with the new configuration
`docker compose up --build --no-deps --detach` 

check the output of the service:
```bash
$ docker compose logs -f
hello_1  | Hello World! Hello Rudi
hello_1  | Hello World! Hello Rudi
...
```
> This is not what we expected!

**We check for anonymous volumes:**
1. get the ID of the container
    ```bash
    $ docker ps        
    CONTAINER ID   IMAGE          COMMAND                  CREATED          STATUS          PORTS     NAMES
    2419dd47277a   696b927fee44   "sh /app/hello-world…"   About a minute ago   Up About a minute             docker-anon-volumes_hello_1
  ```
 2. run the command to list the volumes with your container id `2419dd47277a` from `docker ps`
    ```bash
  $ docker inspect --type container -f '{{range $i, $v := .Mounts }}{{printf "%v\n" $v}}{{end}}' 2419dd47277a
  {volume c62baf7300ddc9dc66a7e871d6511e5e3a6274072cc20c3f14bb59bca5319935 /var/lib/docker/volumes/c62baf7300ddc9dc66a7e871d6511e5e3a6274072cc20c3f14bb59bca5319935/_data /app/config local rw true }
  ```
  **What do we get:**
  1. We have an anonymous volume attached to our container `volume c62baf7300ddc9dc66a7e871d6511e5e3a6274072cc20c3f14bb59bca5319935`
  2. The container ID here `2419dd47277a` is different to the one before `1df0f6ee87d4`. This is a new container with the changes `name.txt`
  3. The content of the anonymous volume is mapped to the `/app/config` directory and is overlaying the new container with the old files

#### Fixing
1. remove the `VOLUME` command if not used
2. add `--renew-anon-volumes` to your `up --build` to [recreate this anonymous volume](https://docs.docker.com/compose/reference/up/)

The number 1 reason why this happens is that you consume a third party image and you did never checked the exported VOLUMES of this image. As you are not in control of this image there is no way to fix this.

**Let's try option 2):**

change the content in file `src/config/name.txt` from `Franz`to `Hans`
`echo "Hans">src/config/name.txt`
_we need to do this as the image has already created with name=Franz and a rebuild would not detect and changes what would lead to the up command not recreating the container and no recreation of the anonymous volumes_

```bash
docker compose up --build --no-deps --detach --renew-anon-volumes
```
check the output of the service:
```bash
$ docker compose logs -f
hello_1  | Hello World! Hello Hans
hello_1  | Hello World! Hello Hans
...
```
This is what we expected from the beginning :-)
