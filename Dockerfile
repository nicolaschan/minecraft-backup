FROM alpine

RUN apk add bash coreutils xxd

WORKDIR /code
COPY ./backup.sh .

ENTRYPOINT ["/code/backup.sh"]
