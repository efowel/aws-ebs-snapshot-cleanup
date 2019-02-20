#!/bin/bash

#######Vars Special Snapshot#######
declare -A special
#Associaltive Array, use [instancename]=devicemapping
#excample special[contentservice]=/dev/sda2
#		  special[myinstace]=/dev/sdz3


#get array size
size=${#special[@]}
###################################

ACCOUNT=$(curl http://169.254.169.254/latest/meta-data/iam/info |grep InstanceProfileArn | cut -d ':' -f 6)
REGION=$(curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')



#######Vars Cleanup Snapshot#######
#get date in seconds
basedate=$(echo $(date -d "-15 days" "+%Y-%m-%d" |xargs date +%s -d))

todate=$(date -d "$dates" +%s)
###################################



backup() { 
	#get instance name with tags Backup:Yes and store them in array instances[]
	instances=($(/bin/aws --region=$REGION ec2  describe-instances --filters Name=tag:Backup,Values=[Yes,yes] --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value' --out text | tr '\r\n' ' '))
	for v in "${instances[@]}"
	do
		#get volume id for each element in instance[]
		volumes=($(/bin/aws --region=$REGION  describe-instances --filters Name=tag:Name,Values=$v --query 'Reservations[*].Instances[*].BlockDeviceMappings[*].[DeviceName,Ebs.VolumeId'] --out text |grep -v ^/dev/sda |cut -f 2))
        for snapshot in "${volumes[@]}"
        do
	        #create snapshot for each volume
	        echo "Creating a snapshot for volume $snapshot..."
	        /bin/aws --region=$REGION ec2 create-snapshot --volume-id $snapshot --description "Automated_Snapshot from volume $snapshot with Instance $v" --out talbe
	        sleep 3s
        done
	done
}

special_backup() {
    #get instance name and store them in array instances[]
    echo "Special Case!"
	if [ $size -lt 1 ]; then
		echo "No spaceial backup was configured"
	else
		echo "Creating a snapshot for configured instance..."
        for i in "${!special[@]}"
        do
            name=$(echo "$i")
            device=$(echo "${special[$i]}")
            echo "instance: $name, devicemap: $device "
            volume=$(/bin/aws --region=$REGION ec2 describe-instances --filters Name=tag:Name,Values=$name --query 'Reservations[*].Instances[*].BlockDeviceMappings[*].[DeviceName,Ebs.VolumeId'] --out text |grep $device |cut -f 2)
            echo "Creating a snapshot for $i..."
            /bin/aws --region=$REGION ec2 create-snapshot --volume-id $volume --description "Automated_Snapshot from volume $snapshot with Instance $device" --out table
            sleep 3s
        done
    fi
}



cleanup() {
	snapshot_id=($(/bin/aws --region=$REGION ec2 describe-snapshots --owner-ids $ACCOUNT  --query 'Snapshots[*].[SnapshotId,Description]' --out text |grep "Automated_Snapshot" | cut -f 1 | tr '\r\n' ' '))
	for id in "${snapshot_id[@]}"
	do
		snapshot_date=$(echo $(/bin/aws --region=$REGION ec2 describe-snapshots --snapshot-id $id --query 'Snapshots[*].StartTime' --out text |  awk -F "T" '{print $1}'))
		#snapshot_sec=$(/bin/aws --region=$REGION ec2 describe-snapshots --snapshot-id $id --query 'Snapshots[*].StartTime' --out text |  awk -F "T" '{print $1}' |xargs date +%s -d)
		snapshot_sec=$(date -d $snapshot_date +%s)
		if [ -n "$1" ]; then
			basedate=$(echo $(date -d "-"$1" days" "+%Y-%m-%d" |xargs date +%s -d))
			if [ $snapshot_sec -le $basedate ]; then
				echo "Deleting snapshot older than $1 days --> $id $snapshot_date "
			else
				echo "Kepping snapshot $id $snapshot_date"
			fi
		elif [ -z "$1" ]; then
			if [ $snapshot_sec -le $basedate ]; then
				echo "Deleting snapshot $id $snapshot_date"
			else
				echo "Keeping snapshot $id $snapshot_date"
			fi

		fi
	done
}



