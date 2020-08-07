FROM alpine

RUN apk add bash coreutils

WORKDIR /code
COPY ./backup.sh .

ENTRYPOINT ["/code/backup.sh"]
