FROM alpine

RUN apk add bash coreutils xxd restic

WORKDIR /code
COPY ./backup.sh .

ENTRYPOINT ["/code/backup.sh"]
