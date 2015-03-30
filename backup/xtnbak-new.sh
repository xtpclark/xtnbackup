#!/bin/bash
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3

EDITOR=vi
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKING=$DIR
HOMEDIR=$DIR
cd $DIR
echo "Working dir is $DIR"

WORKDATE=`/bin/date "+%m%d%y_%s"`
PLAINDATE=`date`

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

runback()
{
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
}




setup()
{
DIRS='archive ini logs'
set -- $DIRS
for i in "$@"
do
 if [ -d $i ];
then
echo "Directory $i exists"
else
echo "$i does not exists, creating."
mkdir -p $i
fi
done
}

enviro()
{
SETS=${WORKING}/ini/settings.ini
}

pre()
{
enviro
echo "Checking environment"
if [ ! -f ~/.xtnback ]
then
echo "Writing .xtnback"
touch ~/.xtnback
setup
setini
s3chk
setcronjob
echo "Checking environment again"
pre
else
enviro
setini
s3chk
# runback
fi
}

setini()
{
echo "Checking Settings"
if [ -e $SETS ]
 then
  echo "${SETS} Exists, reading settings"
source $SETS
DUMPVER=`$PGBIN/pg_dump -V | head -1 | cut -d ' ' -f3`
CN=$CRMACCT
BACKUPACCT=bak_${CN}
WORKDATE=`date "+%m%d%Y"`
LOGFILE="${LOGDIR}/${PGHOST}_BackupStatus_${CN}_${WORKDATE}.log"
GLOBALFILE=${CN}_${PGHOST}_globals_${WORKDATE}.sql

 else
  echo "Creating XTN Backup Config"
  echo "Set the Postgres DB User"
  echo "default: postgres"
read PGUSER

if [ -z $PGUSER ]; then
PGUSER=postgres
fi

 echo "Set the Postgres DB Host"
 echo "default: localhost"
read PGHOST

if [ -z $PGHOST ]; then
PGHOST=localhost
fi

 echo "Set the Postgres DB Port"
 echo "default: 5432"
read PGPORT

if [ -z $PGPORT ]; then
PGPORT=5432
fi

 echo "Set the PG Dump Path"
 echo "default: $(pg_config --bindir)"
read PGBIN

if [ -z $PGBIN ]; then
PGBIN=$(pg_config --bindir)
fi

 echo "Set Database Dump Extension"
 echo "default: backup"
read DUMPEXT

if [ -z $DUMPEXT ]; then
DUMPEXT=backup
fi

 echo "Set the path to Archive Backups in"
 echo "default: ${WORKING}/archive"
read ARCHIVEDIR

if [ -z $ARCHIVEDIR ]; then
ARCHIVEDIR=${WORKING}/archive
fi

 echo "Set how many days of backups to keep locally."
 echo "default: 3"
read DAYSTOKEEP

if [ -z $DAYSTOKEEP ]; then
DAYSTOKEEP=3
fi

 echo "Set the path to store Logs"
 echo "default: ${WORKING}/logs"
read LOGDIR

if [ -z $LOGDIR ]; then
LOGDIR=${WORKING}/logs
fi

 echo "Set your xTuple Account Number"
 echo "Default: xtnbackup. You can also contact xTuple, or accept default"
read CRMACCT

if [ -z $CRMACCT ]; then
CRMACCT=xtnbackup
fi

 echo "Set a Mailer"
 echo "default: /usr/bin/mutt"
read MAILPRGM

if [ -z $MAILPRGM ]; then
MAILPRGM=/usr/bin/mutt
fi

 echo "Set an Email address to send the backup report to"
 echo "default: cloudops@xtuple.com"
read MTO

if [ -z $MTO ]; then
MTO=cloudops@xtuple.com
fi

cat << EOF > $SETS
PGUSER=${PGUSER}
PGHOST=${PGHOST}
PGPORT=${PGPORT}
PGBIN=${PGBIN}
DUMPEXT=${DUMPEXT}
ARCHIVEDIR=${ARCHIVEDIR}
LOGDIR=${LOGDIR}
CRMACCT=${CRMACCT}
MTO=${MTO}
DAYSTOKEEP=${DAYSTOKEEP}
MAILPRGM=${MAILPRGM}

EOF

echo "Wrote: ${SETS}"
fi
}

s3chk()
{
echo "Checking for AWS dependencies"
S3CHK='s3cmd'

for PART in $S3CHK; do

if [ -z `which $PART` ]
then
echo "Cannot find ${PART}! It might be ok."
fi
done

echo "Looks good. Found: ${S3CHK}!"
echo "Checking aws configs"
if [ -f ~/.s3cfg ]
then
echo "Found s3cmd config: ~/.s3cfg"
else
echo "AWS s3cmd won't work! You should create ~/.s3cfg (Run s3cmd --configure ?)"
OPTS='yes no'
  select OPT in $OPTS
    do
       if [ $OPT = 'yes' ]
        then
        s3cmd  --configure
        break
         else
        echo "leaving"
        break 
     fi
     done
fi
}

setcronjob()
{
echo "Let's set what time you'd like the backup to run"
echo ${WORKING}
CRONTASK="${WORKING}/${PROG} -h ${PGHOST} -p ${PGPORT} -d ${CRMACCT} -m null -c ${CRMACCT} ${CRMACCT}"

TASKCHECK=`crontab -l | grep "${CRONTASK}" | wc -l`

if [ $TASKCHECK -gt 0 ]; then
echo "Crontab already exists"
else
echo "Creating Crontab"
echo "Set a time in cron format"
echo "default: 0 0 * * * "
read CRONTIME
 if [[ -z ${CRONTIME} ]]; then
 CRONTIME="0 0 * * *"
 fi
crontab -l | { cat; echo "${CRONTIME} /bin/bash ${CRONTASK}" ; } | crontab -
echo "Crontab Set for ${CRONTIME} /bin/bash ${CRONTASK}"
fi

}

settings()
{
if [ -e $SETS ]
then
pre
else
echo "No Settings, Let's create them"
pre
exit 0;
fi
}

removelog()
{
REMOVALLOG="${LOGDIR}/removal.log"
REMOVELIST=`find ${ARCHIVEDIR}/*.backup -mtime +${DAYSTOKEEP} -exec ls {} \;`
REMOVELISTSQL=`find ${ARCHIVEDIR}/*.sql -mtime +${DAYSTOKEEP} -exec ls {} \;`

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


senddbtos3()
{

STARTRSJOB=`date +%T`
s3cmd put ${BACKUPOUT} ${S3BUCKET}/${BACKUPFILE}
STOPRSJOB=`date +%T`
DBSIZE=`ls -lh ${ARCHIVEDIR}/${BACKUPFILE} | cut -d' ' -f5`

cat << EOF >> ${LOGFILE}
s3Link: ${S3BUCKET}/${BACKUPFILE}
Time: ${STARTRSJOB} / ${STOPRSJOB}
BackupSize: ${DBSIZE}
EOF

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
PGDump Version: ${PGDUMPVER}
======================================
EOF

CUSTLIST=`echo "SELECT datname as "dbname" FROM pg_catalog.pg_database \
           WHERE datname NOT IN('postgres','template0','template1') ORDER BY 1;" | \
            $PGBIN/psql -A -t -h $PGHOST -U $PGUSER -p $PGPORT postgres`


for DB in $CUSTLIST ; do

BACKUPFILE=${CN}_${DB}_${WORKDATE}.backup

STARTDBJOB=`date +%T`
$PGBIN/pg_dump --host $PGHOST  --port $PGPORT --username $PGUSER $DB --format custom --blobs --file ${ARCHIVEDIR}/${BACKUPFILE}
STOPDBJOB=`date +%T`

cat << EOF >> $LOGFILE
Database: ${DB}
BackupFile:${BACKUPFILE}
s3Start:${STARTDBJOB}
s3Stop:${STOPDBJOB}

EOF

S3BUCKET=s3://$BACKUPACCT

BACKUPOUT=${ARCHIVEDIR}/${BACKUPFILE}
GLOBALOUT=${ARCHIVEDIR}/${GLOBALFILE}

senddbtos3
updatextnbu

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


sendglobalstos3()
{

STARTRSJOB=`date +%T`
## s3cmd put ${BACKUPOUT} ${S3BUCKET}/${BACKUPFILE}
s3cmd put ${GLOBALOUT} ${S3BUCKET}/${GLOBALFILE}

STOPRSJOB=`date +%T`
DBSIZE=`ls -lh ${ARCHIVEDIR}/${BACKUPFILE} | cut -d' ' -f5`


}

updatextnbu()
{

curl -X POST \
-d '{"CRMACCT":"'"${CRMACCT}"'", "STORAGEID":2, "CRMACCT_ID":"'"${CRMID}"'", "PGHOST":"'"${PGHOST}"'", "PGPORT":"'"${PGPORT}"'", "PGDB":"'"${PGDB}"'", "BACKUPFILE":"'"${BACKUPFILE}"'", "GLOBALFILE":"'"${GLOBALFILE}"'", "PGVER":"'"${PGDUMPVER}"'", "STARTJOB":"'"${STARTDBJOB}"'", "STOPJOB":"'"${STOPDBJOB}"'", "STARTRS":"'"${STARTRSJOB}"'", "STOPRS":"'"${STOPRSJOB}"'", "DBSIZE":"'"${DBSIZE}"'", "STOREURL":"'${BACKUPACCT}/${BACKUPFILE}'", "WASSPLIT":"'"${WASSPLIT}"'"}' \
http://xtntrack.xtuple.com/ \
--header "Content-Type:application/json"

}


mailcustreport()
{
MAILPRGM=`which mutt`
if [ -z $MAILPRGM ]; then
echo "Couldn't mail anything - no mailer."
echo "Set up Mutt."
true
else

$MAILPRGM -e 'set content_type="text/plain"' $MTO -s "xTuple Nightly Backup Details" < ${LOGFILE}

# $MAILPRGM -s "Nightly backup details for $SERVERNAME" $MTO < $MES
fi


rm ${LOGFILE}


}
pre
settings
removelog
backupdb
backupglobals
  #updatextnbu
  #checks3bucket
sendglobalstos3
mailcustreport

exit 0;
