FROM alpine

LABEL org.opencontainers.image.source=https://github.com/nicolaschan/minecraft-backup

RUN apk add bash coreutils xxd restic util-linux openssh rclone

WORKDIR /code
COPY ./backup.sh .

ENTRYPOINT ["/code/backup.sh"]
