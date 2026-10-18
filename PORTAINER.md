# Deploy MediaPager with Portainer

This guide covers Portainer Stacks on a standalone Docker endpoint using the Compose files in
this repository. It includes both the default SQLite deployment and the bundled PostgreSQL
option. Docker Swarm has different volume and CIFS behavior; these steps target regular Docker
Compose stacks.

## 1. Choose a database stack

Choose one Compose file; the two stacks use separate persistent database volumes and do not
migrate data between each other.

| Deployment | Compose file | Database configuration |
|---|---|---|
| SQLite (default) | `docker-compose.yml` | No PostgreSQL service or database password required. |
| PostgreSQL | `docker-compose.postgres.yml` | Includes a PostgreSQL service; set `POSTGRES_PASSWORD` in Portainer before deploying. |

SQLite is the simplest starting point. Use PostgreSQL if you specifically want the separate
PostgreSQL service and its database volume.

## 2. Create the Stack

1. In Portainer, select the Docker endpoint, then open **Stacks → Add stack**.
2. Name the stack (for example, `mediapager`). Choose **Git Repository** and enter
   `https://github.com/MediaPager/MediaPager.git`, or use **Web editor** and paste the contents
   of the selected Compose file.
3. For a Git-based stack, set the Compose path to `docker-compose.yml` for SQLite or
   `docker-compose.postgres.yml` for PostgreSQL.
4. Add the environment variables described below in the Stack's **Environment variables**
   section. These are Compose substitutions; do not add CIFS credentials to the checked-in YAML.
5. Deploy the Stack. Portainer creates the app, database (PostgreSQL variant), and named
   persistent volumes declared by that Compose file.

## 3. Set Stack environment variables

Set only the values you need. Keep passwords and keys in Portainer's Stack environment settings;
do not commit them to the repository.

Common variables:

| Variable | Use |
|---|---|
| `MEDIAPAGER_PORT` | Host port for the web app (default `8080`). |
| `MEDIAPAGER_BASE_URL` | URL users reach, especially when using a reverse proxy. |
| `MEDIAPAGER_MEDIA_PATH` | Absolute Docker-host path for the host bind-mount media option below (default `./media`). |
| `MEDIAPAGER_SEED_USER` | Initial super-admin email; used only when the selected database has no super-admin. |
| `MEDIAPAGER_SEED_PASS` | Optional initial password for a new database. If omitted, read the generated temporary password from the API container logs. Existing account passwords are unchanged. |

For the PostgreSQL Compose file, set `POSTGRES_PASSWORD` to a strong password. The database name
and user default to `mediapager`; they can be changed with `POSTGRES_DB` and `POSTGRES_USER`.
`POSTGRES_PASSWORD` is not needed for the SQLite stack.

After deployment, open `http://<docker-host>:<MEDIAPAGER_PORT>` (default port `8080`). Sign in
with the seed super-admin, change the initial password, and configure catalogs in Settings.

## 4. Connect catalog media

Media is separate from the persistent application-data volume. The app container reads and writes
catalog paths under `/mnt/media`; create catalogs with container paths such as
`/mnt/media/Movies` and `/mnt/media/TV`.

### Option A: mount the NAS share on the Docker host

Mount the NAS share on the Docker host first, then set `MEDIAPAGER_MEDIA_PATH` to that absolute
host path in the Stack environment variables. Compose bind-mounts it to `/mnt/media`. Ensure the
host mount and NAS share ACL permit the container's API identity to access the required files.

### Option B: define a CIFS volume in the Stack

If the NAS share is mounted directly by Docker, use a stack-managed CIFS volume. In the selected
Compose file, replace the existing media bind-mount entry under `services.mediapager.volumes`:

```yaml
- ${MEDIAPAGER_MEDIA_PATH:-./media}:/mnt/media:rw
```

with:

```yaml
- mediapager-media:/mnt/media:rw
```

Then add this volume to the top-level `volumes:` mapping:

```yaml
  mediapager-media:
    driver: local
    driver_opts:
      type: cifs
      device: "//${MEDIA_CIFS_ADDRESS}/${MEDIA_CIFS_SHARE}"
      o: "username=${MEDIA_CIFS_USER},password=${MEDIA_CIFS_PASSWORD},uid=10001,gid=10001,forceuid,forcegid,file_mode=0664,dir_mode=0775,vers=${MEDIA_CIFS_VERSION}"
```

Set these values in Portainer's Stack environment variables:

| Variable | Value |
|---|---|
| `MEDIA_CIFS_ADDRESS` | NAS hostname or IP address (without the leading `//`). |
| `MEDIA_CIFS_SHARE` | SMB share name; Compose combines it with the address as `//address/share`. |
| `MEDIA_CIFS_USER` / `MEDIA_CIFS_PASSWORD` | Dedicated CIFS account with the required share permissions. |
| `MEDIA_CIFS_VERSION` | The CIFS/SMB version supported by the NAS and selected for the existing mount. |

Use the CIFS version supported by the NAS (or omit `,vers=${MEDIA_CIFS_VERSION}` to allow
negotiation if your NAS supports it).
The CIFS account must still have server-side write permission; the UID/GID and mode options only
control the ownership and permissions presented to Linux clients. Use a dedicated account limited
to the media share. Portainer Stack variables keep credentials out of the Compose text but are not
an encrypted secret store; Docker administrators can inspect volume driver options.

A Portainer-created external CIFS volume can also be referenced from Compose, but declaring it
`external: true` only attaches it: it does not apply `driver_opts` from the Stack. If you need
UID/GID or mode options that Portainer's volume form does not expose, define a new stack-managed
volume as above and switch the service mount to it. Leave the old volume in place until the new
mount has been tested. Portainer's volume **Access Control** is not the NAS filesystem ACL.

## 5. Verify media write access

The runtime image creates `mediapager` as UID/GID `10001:10001` and runs the API as that
unprivileged user. Docker's `:rw` flag only avoids a read-only mount; it does not grant this user
permission to create files. Both the CIFS mount's local ownership/modes and the NAS account's
share ACL must allow access. For rootless Docker or user-namespace remapping, use the effective
mapped host IDs instead.

From the Docker host, test creating and removing a temporary file as the API UID. Replace the
container name with the one shown in Portainer:

```sh
docker exec --user 10001:10001 <mediapager-container> sh -c 'id; ls -ldn /mnt/media/Movies; f=$(mktemp /mnt/media/Movies/.mediapager-test.XXXXXX) && rm "$f" && printf "write test passed\\n"'
```

Run a similar check for each destination directory. If it reports `Permission denied`, verify
the in-container path, CIFS mount options, and NAS ACL. A successful write as host root does not
prove that UID 10001 can write. Do not use `chmod 777`, blindly `chown` a CIFS mount, or run the
API as root to work around a permission mismatch.

## 6. Keep data persistent and update

The Compose files declare persistent volumes for application state and, in the PostgreSQL
variant, the database. Redeploying the Stack keeps named volumes. Do not use a volume-removing
operation such as `docker compose down -v` unless you intend to delete the data. Back up the
application data and the database before changing database variants or replacing volumes.
