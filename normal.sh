cd $BACKUP_DIR &>>$LOGFILE
if [ $? -eq 0 ]
then
    echo -e "We are at ${BACKUP_DIR}"
else 
    cd $BACKUP_DIR
fi