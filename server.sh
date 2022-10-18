#!/bin/bash

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
  set_secret "GHOST_DB_PASSWORD"
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

setup() {
  ensure_not_empty "$1" "Please provide a root domain name."
  ensure_not_empty "$2" "Please provide an email address for Let's Encrypt."
  echo "Initializing default configuration..."
  copy_env_file
  set_root_domain $1
  set_letsencrypt_email $2
  set_secrets
  echo "Default configuration file created. Feel free to modify values as needed."
}

case "$1" in
  "create-subscription" | "create_subscription")
    create_subscription $2
    ;;
  "secret" | "set-secret" | "set_secret")
    set_secret $2
    ;;
  "secrets" | "set-secrets" | "set_secrets")
    set_secrets
    ;;
  "setup")
    setup $2 $3
    ;;
  *)
    echo "Unknown command"
    ;;
esac
