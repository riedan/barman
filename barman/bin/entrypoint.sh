#!/usr/bin/env bash
set -e

if [ "$(ls -A /certs/)" ]; then
  cp /certs/* /usr/local/share/ca-certificates/
  update-ca-certificates
fi

getent group ${SYS_GROUP} || addgroup -S ${SYS_GROUP}
getent passwd ${SYS_USER} || adduser -S ${SYS_USER}  -G ${SYS_GROUP} -s "/bin/bash" -h "/home/barman"

chown -Rf ${SYS_USER}:${SYS_GROUP} /home/barman || true
chown  ${SYS_USER}:${SYS_GROUP} $BACKUP_DIR || true


echo ">>> Checking all configurations"
[[ "$REPLICATION_HOST" != "" ]] || ( echo 'Variable REPLICATION_HOST is not set!' ;exit 1 )
[[ "$POSTGRES_USER" != "" ]] || ( echo 'Variable POSTGRES_USER is not set!' ;exit 2 )
[[ "$POSTGRES_PASSWORD" != "" ]] || ( echo 'Variable POSTGRES_PASSWORD is not set!' ;exit 3 )
[[ "$POSTGRES_DB" != "" ]] || ( echo 'Variable POSTGRES_DB is not set!' ;exit 4 )

echo ">>> Configuring barman for streaming replication"
echo "
[$UPSTREAM_NAME]
description =  'Cluster $UPSTREAM_NAME replication'
backup_method = postgres
streaming_archiver = on
streaming_archiver_name = barman_receive_wal
streaming_archiver_batch_size = 50
streaming_conninfo = host=$REPLICATION_HOST user=$REPLICATION_USER password=$REPLICATION_PASSWORD port=$REPLICATION_PORT sslmode=prefer
conninfo = host=$REPLICATION_HOST dbname=$POSTGRES_DB user=$POSTGRES_USER password=$POSTGRES_PASSWORD port=$REPLICATION_PORT connect_timeout=$POSTGRES_CONNECTION_TIMEOUT sslmode=prefer
slot_name = $REPLICATION_SLOT_NAME
backup_directory = $BACKUP_DIR
retention_policy = RECOVERY WINDOW OF $BACKUP_RETENTION_DAYS DAYS
" >> $UPSTREAM_CONFIG_FILE



sed -i "s/#*\(barman_user\).*/\1 = '${SYS_USER}'/;" /etc/barman.conf

rm -rf /var/spool/cron/crontabs/*
echo '>>> SETUP BARMAN CRON'
echo ">>>>>> Backup schedule is $BACKUP_SCHEDULE"
echo  "*/1 * * * * cd /home/barman && /usr/local/bin/barman_docker/wal-receiver.sh" > /var/spool/cron/crontabs/${SYS_USER}
echo "$BACKUP_SCHEDULE barman backup all" >> /var/spool/cron/crontabs/${SYS_USER}
chmod 0644 /var/spool/cron/crontabs/${SYS_USER}


echo '>>> STARTING METRICS SERVER'
/go/main &


su-exec  ${SYS_USER} /usr/local/bin/barman_docker/wal-receiver.sh

if [ -d "$BACKUP_DIR/base" ]; then
  barman switch-wal --force --archive $UPSTREAM_NAME
fi

echo '>>> STARTING CRON'
env >> /etc/environment
crond -f -l 4 -d 4 -L /var/log/barman.log

