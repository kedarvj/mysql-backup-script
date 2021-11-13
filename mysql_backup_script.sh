#/bin/bash
## Script: 
# Backup script to take mysqldump
# Retain 7 days of backup
# Move backup to offsite
# Send out success/failure email
# http://kedar.nitty-witty.com/blog
## Ver.1 2018-01-20

#  set up all the mysqldump variables
FILE=database.sql.`date +"%Y%m%d"`.gz
DBSERVER=127.0.0.1
REMOTE_SERVER=127.0.0.1 # move database to offsite for backup
DATABASE=dbname
DBUSER=backup_user
PASS=s3cr3tp@ssw0rd

SRC_DIR=/home/admin/script
REMOTE_BACKUP_DIR=/root/mysql/backup
NOW=`date "+%Y%m%d-%H%M"`
email_list="kedar@nitty-witty.com"
success_email="kedar+success@nitty-witty.com"
failure_email="kedar+failure@nitty-witty.com";
START=$(date +%s)

# function to send backup status email
sendEmail() {
        scripttime=0;
        END=$(date +%s)
        DIFF=$(( $END - $START ))
        if [ $DIFF -le 60 ]; then
                scripttime="$DIFF seconds.";
        else
                DIFF=$(( $DIFF / 60 ))
                scripttime="$DIFF minutes.";
        fi;
        content="$content. Log: Backup duration: $scripttime"
        echo $content  | mail -s "$subject"  $email_list
        exit;
}

motd() {
# To enable MOTD, uncomment the function calls
    MOTD="\n\n\n\n####################################\n"
    MOTD="$MOTD  IMPORTANT: BACKUPS\n"
    MOTD="####################################\n"
    MOTD="$MOTD Backup script is at: $SRC_DIR\n"
    MOTD="$MOTD Local backup stored at: $SRC_DIR\n"
    MOTD="$MOTD Remote backup stored at: $REMOTE_BACKUP_DIR\n"
    MOTD="$MOTD Remote backup server is: 192.154.230.46\n"
    MOTD="$MOTD Last Backup Status on $NOW: $content \n"
    MOTD="$MOTD####################################\n"
    echo -e "$MOTD" > /etc/motd
}

# pipeline will return failure code if the mysqldump command fails
set -o pipefail
# Taking backup of all databases
mysqldump --opt --user=${DBUSER} --password=${PASS} --no-data --single-transaction --all-databases | gzip > ${SRC_DIR}/${FILE} 2>/dev/null

# Verify backup is success/failure
RESULT=$?
if [ $RESULT -ne 0 ]; then
        subject="Backup-FAILURE";
        content="Backup appears to have been failed for $NOW. The mysqldump command returned failure status. Please login to $DBSERVER and check the status."
        email_list=$failure_email
        echo "[`date`]Backup failure."
#        motd # Uncomment if you want to change MOTD
        sendEmail
fi

# Transfer to remote host
scp ${SRC_DIR}/${FILE} root@${REMOTE_SERVER}:${REMOTE_BACKUP_DIR} 2>/dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
        subject="Backup-FAILURE";
        content="Backup appears to have been completed for $NOW. But SCP to remote server failed."
        email_list=$failure_email
        echo "[`date`]SCP failure."
#        motd # Uncomment if you want to change MOTD
        sendEmail
fi

# Delete 7 days old file from remote host
BACKUP_FILE=${REMOTE_BACKUP_DIR}/database.sql.`date -d"-7 days" +"%Y%m%d"`.gz 2>/dev/null
# in case you run this more than once a day, remove the previous version of the file
echo "[`date`] Removing backup file: $BACKUP_FILE from ${REMOTE_SERVER}."
ssh root@${REMOTE_SERVER} "rm $BACKUP_FILE" 2>/dev/null

# Keep only last 7 days worth backup on database server.
find $SRC_DIR -mtime +7 -name '*.gz' -exec rm {} \;

# Finally send successful backup completion email.
subject="Backup-SUCCESS"
content="The backup file is on database server $SRC_DIR/$FILE. Remote location is Backup ${REMOTE_SERVER}:$REMOTE_BACKUP_DIR is successful."
content=$content.`ls -lhtr $SRC_DIR/ | awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,"\r"}'`
email_list=$success_email;
echo "[`date`]Backup Success."
#motd # Uncomment if you want to change MOTD
sendEmail
exit 0;
