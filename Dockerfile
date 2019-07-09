FROM golang:alpine

ENV SYS_USER barman
ENV SYS_GROUP barman

#create user if not exist
RUN set -eux; \
	getent group ${SYS_GROUP} || addgroup -S ${SYS_GROUP}; \
	getent passwd ${SYS_USER} || adduser -S ${SYS_USER}  -G ${SYS_GROUP} -s "/bin/bash" -h /home/postgres/;


RUN set -ex \
	\
	&& apk add --no-cache  ca-certificates su-exec bash inotify-tools \
	                        postgresql-client \
	&& apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --allow-untrusted barman

ADD barman/crontab /etc/cron.d/barman

RUN rm -f /etc/cron.daily/*

ENV UPSTREAM_NAME pg_cluster
ENV UPSTREAM_CONFIG_FILE /etc/barman.d/upstream.conf
ENV REPLICATION_USER replication_user
ENV REPLICATION_PASSWORD replication_pass
ENV REPLICATION_PORT 5432
ENV POSTGRES_CONNECTION_TIMEOUT 20
ENV REPLICATION_SLOT_NAME barman_the_backupper
ENV WAIT_UPSTREAM_TIMEOUT 60
ENV SSH_ENABLE 0
ENV NOTVISIBLE "in users profile"
ENV BACKUP_SCHEDULE "0 0 * * *"
ENV BACKUP_RETENTION_DAYS "30"
ENV BACKUP_DIR /var/backups

# REQUIRED ENV VARS:
# ENV REPLICATION_HOST localhost
# ENV POSTGRES_USER postgres
# ENV POSTGRES_PASSWORD password
# ENV POSTGRES_DB monkey_db

EXPOSE 22


COPY ./barman/configs/barman.conf /etc/barman.conf
COPY ./barman/configs/upstream.conf $UPSTREAM_CONFIG_FILE
COPY ./barman/bin /usr/local/bin/barman_docker
RUN chmod +x /usr/local/bin/barman_docker/* && ls /usr/local/bin/barman_docker

COPY ./barman/metrics /go
RUN cd /go && go build /go/main.go

VOLUME $BACKUP_DIR

CMD /usr/local/bin/barman_docker/entrypoint.sh