FROM docker:27.4.0-rc.1-dind
RUN apk update && apk add bash jq aws-cli
VOLUME /tmp/repos
ADD docker.sh bin
