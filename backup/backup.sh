#!/bin/bash
PROG=`basename $0`

usage() {
  echo "$PROG usage:"
  echo
  echo "$PROG -H"
  echo "$PROG [ -h hostname ] [ -p port ] [ -d database ] [ -m user@company.com ] [ -c CRMACCNTNAME ] companyname"
  echo
  echo "-H      print this help and exit"
  echo "-h      hostname of the database server (default $PGHOST)"
  echo "-p      listening port of the database server (default $PGPORT)"
  echo "-d      name of database"
  echo "-m      Notification Email recipient"
  echo "-c      CRMACCOUNT Name"
  echo " Last value is company name, becomes bak_companyname"
}

ARGS=`getopt Hh:p:d:m:c: $*`

if [ $? != 0 ] ; then
usage
exit 1
fi

set -- $ARGS

while [ "$1" != -- ] ; do
  case "$1" in
    -H)   usage ; exit 0 ;;
    -h)   export PGHOST="$2" ; shift ;;
    -p)   export PGPORT="$2" ; shift ;;
    -d)   export PGDB="$2" ; shift ;;
    -m)   export NOTE="$2" ; shift ;;
    -c)   export CRMACCT="$2" ; shift ;;
    *)    usage ; exit 1 ;;
  esac
  shift
done
shift

if [ $# -lt 1 ] ; then
  echo $PROG: One db to backup is required
  usage
  exit 1
elif [ $# -gt 1 ] ; then
  echo $PROG: multiple dbs named - ignoring more than the first 1
fi



PGBIN=/usr/bin
WORKDATE=`/bin/date "+%m%d%Y"`
DUMPVER=`$PGBIN/pg_dump -V | head -1 | cut -d ' ' -f3`
PGUSER=postgres
PGHOST=localhost
DUMPEXT=backup
CN=$CRMACCT
BACKUPACCT=bak_${CN}
PGBIN=/usr/bin
PGUSER=postgres
WORKDATE=`date "+%m%d%Y"`

HOMEDIR=/mnt
BACKUPDIR=$HOMEDIR/backup
ARCHIVEDIR=$BACKUPDIR/archive
LOGDIR=${BACKUPDIR}/logs
LOGFILE="${LOGDIR}/${PGHOST}_BackupStatus_${CN}_${WORKDATE}.log"

GLOBALFILE=${CN}_${PGHOST}_globals_${WORKDATE}.sql

mail()
{
#=====
# Mail
#=====
MAILPRGM=/usr/bin/mutt
export EMAIL=mail@domain.com
MTO="user@domain.com"
}

removelog()
{
REMOVALLOG="${LOGDIR}/removal.log"
REMOVELIST=`find ${ARCHIVEDIR}/*.backup -mtime +1 -exec ls {} \;`
REMOVELISTSQL=`find ${ARCHIVEDIR}/*.sql -mtime +1 -exec ls {} \;`

cat << EOF >> $REMOVALLOG
========================================
REMOVAL LOG FOR $WORKDATE
========================================
EOF

for REMOVEME in $REMOVELIST ; do
rm -rf $REMOVEME
cat << EOF >> $REMOVALLOG
$REMOVEME Deleted
EOF
done

for REMOVEMESQL in $REMOVELISTSQL ; do
rm -rf $REMOVEMESQL
cat << EOF >> $REMOVALLOG
$REMOVEMESQL Deleted
EOF
done
}


backupdb()
{
#==============
# Loop through database names and back them up.
# Make list of databases to backup individually.
#==============
PGDUMPVER=`pg_dump -V`

STARTJOB=`date +%T`

cat << EOF >> $LOGFILE
======================================
Backup Job Started: $WORKDATE $STARTJOB
======================================
EOF

CUSTLIST=`echo "SELECT datname as "dbname" FROM pg_catalog.pg_database \
           WHERE datname IN('${PGDB}') ORDER BY 1;" | \
            $PGBIN/psql -A -t -h $PGHOST -U $PGUSER -p $PGPORT postgres`


for DB in $CUSTLIST ; do

BACKUPFILE=${CN}_${DB}_93_${WORKDATE}.backup

STARTDBJOB=`date +%T`
$PGBIN/pg_dump --host $PGHOST  --port $PGPORT --username $PGUSER $DB --format custom --blobs --file ${ARCHIVEDIR}/${BACKUPFILE}
STOPDBJOB=`date +%T`

S3BUCKET=s3://$BACKUPACCT

BACKUPOUT=${ARCHIVEDIR}/${BACKUPFILE}
GLOBALOUT=${ARCHIVEDIR}/${GLOBALFILE}

done
}

backupglobals()
{
#==============
# Grab the Globals too
#==============

$PGBIN/pg_dumpall -U $PGUSER -h $PGHOST -p $PGPORT -g > ${ARCHIVEDIR}/${GLOBALFILE}

cat << EOF >> $LOGFILE
Globals: $GLOBALFILE
==================================
EOF

}

checks3bucket()
{

s3cmd info ${S3BUCKET} > /dev/null 2>&1
# s3cmd info ${S3BUCKET}

#if [[ $? -eq 0 ]]; then
#echo "Bucket looks OK"
#else
  s3cmd mb ${S3BUCKET}
#echo "Created bucket"
  sleep 10
#fi

}

sendtos3()
{

STARTRSJOB=`date +%T`
s3cmd put ${BACKUPOUT} ${S3BUCKET}/${BACKUPFILE}
s3cmd put ${GLOBALOUT} ${S3BUCKET}/${GLOBALFILE}

STOPRSJOB=`date +%T`
DBSIZE=`ls -lh ${ARCHIVEDIR}/${BACKUPFILE} | cut -d' ' -f5`


}

updatextnbu()
{
UPDATEXTNBU=${LOGDIR}/${CN}_${PGDB}_${WORKDATE}.qry

cat << EOF >> $UPDATEXTNBU
CRMACCT~'${CRMACCT}'
STORAGEID~2
CRMACCT_ID~'${CRMID}'
PGHOST~'${PGHOST}'
PGPORT~'${PGPORT}'
PGDB~'${PGDB}'
BACKUPFILE~'${BACKUPFILE}'
GLOBALFILE~'${GLOBALFILE}'
PGVER~'${PGDUMPVER}'
STARTJOB~'${STARTDBJOB}'
STOPJOB~'${STOPDBJOB}'
STARTRS~'${STARTRSJOB}'
STOPRS~'${STOPRSJOB}'
DBSIZE~'${DBSIZE}'
STOREURL~'${BACKUPACCT}/${BACKUPFILE}'
WASSPLIT~'$WASSPLIT'
EOF
}

removelog
backupglobals
backupdb
updatextnbu
checks3bucket
sendtos3

exit 0;
