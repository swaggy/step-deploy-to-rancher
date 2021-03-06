#!/bin/bash -e

# Have access to the following variables
# $WERCKER_DEPLOY_TO_RANCHER_ACCESS_KEY
# $WERCKER_DEPLOY_TO_RANCHER_SECRET_KEY
# $WERCKER_DEPLOY_TO_RANCHER_RANCHER_URL
# $WERCKER_DEPLOY_TO_RANCHER_HTTPS
# $WERCKER_DEPLOY_TO_RANCHER_TAG
# $WERCKER_DEPLOY_TO_RANCHER_STACK_NAME
# $WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME
# $WERCKER_DEPLOY_TO_RANCHER_DOCKER_ORG
# $WERCKER_DEPLOY_TO_RANCHER_DOCKER_IMAGE
# $WERCKER_DEPLOY_TO_RANCHER_USE_TAG
# $WERCKER_DEPLOY_TO_RANCHER_INPLACE
# $WERCKER_DEPLOY_TO_RANCHER_START_FIRST

if [ "$WERCKER_DEPLOY_TO_RANCHER_USE_TAG" == true ]; then
    export DTR_SUFFIX="$WERCKER_DEPLOY_TO_RANCHER_TAG";
else
    export DTR_SUFFIX=$RANDOM;
fi

if [ "$WERCKER_DEPLOY_TO_RANCHER_HTTPS" == true ]; then
    export DTR_PROTO=https;
else
    export DTR_PROTO=http;
fi

function get_env_id { curl -s "$DTR_PROTO://$WERCKER_DEPLOY_TO_RANCHER_ACCESS_KEY:$WERCKER_DEPLOY_TO_RANCHER_SECRET_KEY@$WERCKER_DEPLOY_TO_RANCHER_RANCHER_URL/environments?name=$WERCKER_DEPLOY_TO_RANCHER_STACK_NAME" | "$WERCKER_STEP_ROOT/jq" '.data[0].id' | sed s/\"//g; }

DTR_ENV_ID=$(get_env_id)

wget -qO file.zip "$DTR_PROTO://$WERCKER_DEPLOY_TO_RANCHER_ACCESS_KEY:$WERCKER_DEPLOY_TO_RANCHER_SECRET_KEY@$WERCKER_DEPLOY_TO_RANCHER_RANCHER_URL/environments/$DTR_ENV_ID/composeconfig"
"$WERCKER_STEP_ROOT/unzip" -o file.zip

if [ "$WERCKER_DEPLOY_TO_RANCHER_INPLACE" != true ]; then
  function get_old_service_name { sed -n "s/^\($WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME[^:]*\):[\r\n]$/\1/p" docker-compose.yml; }

  DTR_OLD_SERVICE_NAME=$(get_old_service_name)
fi


if [ "$WERCKER_DEPLOY_TO_RANCHER_INPLACE" != true ]; then
  # Update docker-compose.yml to include new service name
  sed -i "s/^$DTR_OLD_SERVICE_NAME:/$DTR_OLD_SERVICE_NAME:\r\n$WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME-$DTR_SUFFIX:/g" docker-compose.yml
  sed -i "s/^$DTR_OLD_SERVICE_NAME:/$DTR_OLD_SERVICE_NAME:\r\n$WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME-$DTR_SUFFIX:/g" rancher-compose.yml
fi

# Update image in docker-compose.yml
sed -i "s/^\(\s *image: $WERCKER_DEPLOY_TO_RANCHER_DOCKER_ORG\/$WERCKER_DEPLOY_TO_RANCHER_DOCKER_IMAGE\).*$/\1:$WERCKER_DEPLOY_TO_RANCHER_TAG/g" docker-compose.yml

if [ "$WERCKER_DEPLOY_TO_RANCHER_START_FIRST" == true ]; then
    # Add start first directive to rancher-compose.yml.
    sed -i "s/\(^[a-zA-Z].*:\)/\1\r\n  upgrade_strategy:\r\n    start_first: true/g" rancher-compose.yml
fi
if [ "$WERCKER_DEPLOY_TO_RANCHER_INPLACE" == true ]; then
  echo "Starting upgrade..."
  "$WERCKER_STEP_ROOT/rancher-compose" --url "$DTR_PROTO://$WERCKER_DEPLOY_TO_RANCHER_RANCHER_URL" --access-key "$WERCKER_DEPLOY_TO_RANCHER_ACCESS_KEY" --secret-key "$WERCKER_DEPLOY_TO_RANCHER_SECRET_KEY" --project-name "$WERCKER_DEPLOY_TO_RANCHER_STACK_NAME" up -d --upgrade --pull --interval 30000 --batch-size 1 "$WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME"
  echo "Done."
  if [ "$WERCKER_DEPLOY_TO_RANCHER_START_FIRST" == false ]; then
    # Have to wait before confirming because the pull and launch will happen asyncronously.
      echo "Waiting 60 seconds to confirm upgrade..."
      sleep 60
  fi
  echo "Confirming upgrade..."
  "$WERCKER_STEP_ROOT/rancher-compose" --url "$DTR_PROTO://$WERCKER_DEPLOY_TO_RANCHER_RANCHER_URL" --access-key "$WERCKER_DEPLOY_TO_RANCHER_ACCESS_KEY" --secret-key "$WERCKER_DEPLOY_TO_RANCHER_SECRET_KEY" --project-name "$WERCKER_DEPLOY_TO_RANCHER_STACK_NAME" up -d --upgrade --confirm-upgrade "$WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME"
  echo "Done."
else
  "$WERCKER_STEP_ROOT/rancher-compose" --url "$DTR_PROTO://$WERCKER_DEPLOY_TO_RANCHER_RANCHER_URL" --access-key "$WERCKER_DEPLOY_TO_RANCHER_ACCESS_KEY" --secret-key "$WERCKER_DEPLOY_TO_RANCHER_SECRET_KEY" --project-name "$WERCKER_DEPLOY_TO_RANCHER_STACK_NAME" upgrade "$DTR_OLD_SERVICE_NAME" "$WERCKER_DEPLOY_TO_RANCHER_SERVICE_NAME-$DTR_SUFFIX" --pull --update-links -c --interval 30000 --batch-size 1
fi
