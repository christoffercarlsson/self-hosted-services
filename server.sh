#!/bin/bash

DEFAULT_PATH="$HOME/.self-hosted-services"

SCRIPT_DIRECTORY=$(realpath -s $(dirname $0))
ENV_FILE="$SCRIPT_DIRECTORY/.env"
SAMPLE_ENV_FILE="$SCRIPT_DIRECTORY/sample.env"

SED_COMMAND="sed -i"
if [[ "$(uname)" == "Darwin" ]]
then
  SED_COMMAND="sed -i ''"
fi

copy_env_file() {
  cp -n $SAMPLE_ENV_FILE $ENV_FILE
}

ensure_last_success() {
  if [ "$?" -ne "0" ]
  then
    echo "$1"
    exit 1
  fi
}

ensure_not_empty() {
  if [[ -z "$1" ]]
  then
    echo "$2"
    exit 1
  fi
}

check_config_file_changes() {
  if [[ ! -f "$ENV_FILE" ]]
  then
    echo "Could not find environment file."
    echo "Please run the './server.sh setup' command and try again."
    exit 1
  fi
  local sample_env_lines=$(wc -l "$SAMPLE_ENV_FILE" | awk '{ print $1 }')
  local env_lines=$(wc -l "$ENV_FILE" | awk '{ print $1 }')
  if [[ "$sample_env_lines" -ne "$env_lines" ]]
  then
    echo "The environment file contains a different amount of lines than \
    the sample file. There may be a new environment variable to configure."
    echo "Please update your environment file and try again."
    exit 1
  fi
}

create_subscription() {
  ensure_not_empty "$1" "Please provide an email for the subscription."
  echo "Creating Standard Notes subscription."
  docker compose exec notes-db sh -c "MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql \$MYSQL_DATABASE -e \
    'INSERT INTO user_roles (role_uuid , user_uuid) VALUES (\
    (SELECT uuid FROM roles WHERE name=\"PRO_USER\" ORDER BY version DESC limit 1), \
    (SELECT uuid FROM users WHERE email=\"$1\")\
    ) ON DUPLICATE KEY UPDATE role_uuid = VALUES(role_uuid);'\
  "
  ensure_last_success "Failed to create user role."
  docker compose exec notes-db sh -c "MYSQL_PWD=\$MYSQL_ROOT_PASSWORD mysql \$MYSQL_DATABASE -e \
    'INSERT INTO user_subscriptions SET \
    uuid=UUID(), \
    plan_name=\"PRO_PLAN\", \
    ends_at=8640000000000000, \
    created_at=0, \
    updated_at=0, \
    user_uuid=(SELECT uuid FROM users WHERE email=\"$1\"), \
    subscription_id=1, \
    subscription_type=\"regular\";'\
  "
  ensure_last_success "Failed to create user subscription."
  echo "Subscription successfully created."
  echo "Please consider donating to Standard Notes if you do not plan on purchasing a subscription."
}

set_placeholder() {
  local value=$(echo $1 | tr '[:upper:]' '[:lower:]')
  eval $SED_COMMAND "s#$value#$2#g" $ENV_FILE
}

set_domain_key() {
  ensure_not_empty "$1" "Please provide a service to set the domain key for."
  ensure_not_empty "$2" "Please provide a domain key."
  set_placeholder "$1_DOMAIN_KEY" $2
}

set_letsencrypt_email() {
  set_placeholder "LETSENCRYPT_EMAIL" $1
}

set_root_domain() {
  set_placeholder "ROOT_DOMAIN" $1
}

set_secret() {
  set_placeholder $1 $(openssl rand -hex 32)
}

set_secrets() {
  set_secret "NEXTCLOUD_DB_PASSWORD"
  set_secret "NOTES_AUTH_JWT_SECRET"
  set_secret "NOTES_DB_PASSWORD"
  set_secret "NOTES_ENCRYPTION_SERVER_KEY"
  set_secret "NOTES_JWT_SECRET"
  set_secret "NOTES_LEGACY_JWT_SECRET"
  set_secret "NOTES_PSEUDO_KEY_PARAMS_KEY"
  set_secret "NOTES_SECRET_KEY_BASE"
  set_secret "NOTES_VALET_TOKEN_SECRET"
}

set_paths() {
  local path
  if [[ -z "$1" ]]
  then
    path=$DEFAULT_PATH
  else
    path=$(realpath -s $1)
  fi
  set_placeholder "LETSENCRYPT_PATH" "$path/letsencrypt"
  set_placeholder "DDNS_UPDATER_PATH" "$path/ddns-updater"
  set_placeholder "BITWARDEN_PATH" "$path/bitwarden"
  set_placeholder "JELLYFIN_CACHE_PATH" "$path/jellyfin/cache"
  set_placeholder "JELLYFIN_CONFIG_PATH" "$path/jellyfin/config"
  set_placeholder "JELLYFIN_MEDIA_PATH" "$path/jellyfin/media"
  set_placeholder "NEXTCLOUD_APP_PATH" "$path/nextcloud/app"
  set_placeholder "NEXTCLOUD_CONFIG_PATH" "$path/nextcloud/config"
  set_placeholder "NEXTCLOUD_DB_PATH" "$path/nextcloud/db"
  set_placeholder "NEXTCLOUD_REDIS_PATH" "$path/nextcloud/redis"
  set_placeholder "NOTES_DATA_PATH" "$path/notes/data/mysql"
  set_placeholder "NOTES_DATA_IMPORT_PATH" "$path/notes/data/import"
  set_placeholder "NOTES_FILE_UPLOAD_PATH" "$path/notes/data/uploads"
  set_placeholder "NOTES_REDIS_PATH" "$path/notes/redis"
  set_placeholder "UPTIME_KUMA_PATH" "$path/uptime-kuma"
}

setup() {
  ensure_not_empty "$1" "Please provide a root domain name."
  ensure_not_empty "$2" "Please provide an email address for Let's Encrypt."
  echo "Initializing default configuration."
  copy_env_file
  set_root_domain $1
  set_letsencrypt_email $2
  set_paths $3
  set_secrets
  echo "Default configuration file created. Feel free to modify values as needed."
}

start_services() {
  echo "Starting up infrastructure."
  docker compose up -d
  ensure_last_success "Failed to start infrastructure."
  echo "Infrastructure started. Give it a moment to warm up."
  echo "Run the './server.sh logs' command to see details."
}

stop_services() {
  echo "Stopping all services."
  docker compose kill || true
  ensure_last_success "Failed to stop services."
  echo "Services stopped."
}

pull_git_changes() {
  echo "Pulling changes from Git."
  git pull origin $(git rev-parse --abbrev-ref HEAD)
  ensure_last_success "Failed to pull latest changes from Git."
}

pull_images() {
  echo "Downloading latest images."
  docker compose pull
  ensure_last_success "Failed to download latest images."
}

case "$1" in
  "create-subscription" | "create_subscription")
    create_subscription $2
    ;;
  "domain-key" | "domain_key" | "set-domain-key" | "set_domain_key")
    check_config_file_changes
    set_domain_key $2 $3
    ;;
  "logs")
    docker compose logs -f
    ;;
  "setup")
    setup $2 $3 $4
    ;;
  "start")
    check_config_file_changes
    start_services
    ;;
  "stop")
    stop_services
    ;;
  "update")
    stop_services
    pull_git_changes
    pull_images
    echo "Infrastructure up to date."
    echo "Run the './server.sh start' command to bring it back up."
    ;;
  *)
    echo "Unknown command"
    ;;
esac
