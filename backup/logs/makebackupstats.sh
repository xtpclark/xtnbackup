#!/bin/bash
WORKDATE=`/bin/date "+%m%d%Y"`
HOSTNAME=thymly
WORKDIR="/mnt/backup/logs"
ARCHDIR=${WORKDIR}/archive
S3BUCKET="s3://${HOSTNAME}_tarpack"

cd $WORKDIR
QUERYFILES=`ls *.qry`
LOGFILES=`ls *.log`

TARFILE=${HOSTNAME}_${WORKDATE}.tar
TARPACK=${ARCHDIR}/${TARFILE}

LOGPACK=${ARCHDIR}/${HOSTNAME}_${WORKDATE}_logs.tar

# echo $QUERYFILES

QUERYFILESCNT=( $QUERYFILES )
QUERYITEMCNT=${#QUERYFILESCNT[@]}

# echo $QUERYITEMCNT

if [ $QUERYITEMCNT -gt 0 ]
then
tar -cf $TARPACK $QUERYFILES
tar -czf $LOGPACK $LOGFILES

s3cmd put $TARPACK ${S3BUCKET}/${TARFILE}

for FILE in $QUERYFILES ; do
rm $FILE
done

# cat << EOF > ${ARCHDIR}/manifest
# IPADDR~nova4.xtuple.com
# PORT~22
# SCPDIR~$TARPACK
# EOF

for LOGFILE in $LOGFILES ; do
rm $LOGFILE
done


exit 0;

else

exit 0;
fi
