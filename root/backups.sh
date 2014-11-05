#!/bin/bash
WORKDATE=`date "+%m%d%Y"`
WORKDIR=/mnt/backup/logs
BACKUPJOBRPT=${WORKDIR}/backupjobs.log
<<<<<<< HEAD
MTO=email@user.com
=======
MTO=cloudops@xtuple.com
>>>>>>> 7029bc053b04004f300a715cc81083df42d03fb5
SERVERNAME=thymly

runbackups()
{
STARTJOB=`date +%T`
/bin/sh /mnt/backup/backup.sh -h localhost -p 5432 -d tpi_live -m null -c thymly thymly

/bin/bash /mnt/backup/logs/makebackupstats.sh

STOPJOB=`date +%T`
}

makereport()
{
rm $BACKUPJOBRPT

EC2DATA=`ec2metadata --instance-id --local-ipv4 --public-ipv4 --availability-zone`

INSTANCEID=`ec2metadata --instance-id`
cat << EOF >> $BACKUPJOBRPT
Backups ran $WORKDATE
Start / Stop Job: $STARTJOB / $STOPJOB

==EC2Data==
$EC2DATA

EOF
}

mailcustreport()
{
MAILPRGM=`which mutt`
if [ -z $MAILPRGM ]; then
echo "Couldn't mail anything - no mailer."
echo "Set up Mutt."
true
else
MSUB="Nightly backup details for $SERVERNAME"
MES="${BACKUPJOBRPT}"

$MAILPRGM -s "Nightly backup details for $SERVERNAME" $MTO < $MES
fi
}

runbackups
makereport
mailcustreport

exit 0;



