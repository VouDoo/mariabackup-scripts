#!/bin/bash
#
# perform a backup of the MariaDB instance with Mariabackup.

### GLOBAL VARIABLES ###

# path to the directory where mariabackup stores the backup files
BACKUP_DIR="/var/lib/mariabackup/backup"

### SCRIPT ARGUMENTS ###

usage()
{
    echo "Usage: $0 {full|incremental}" 1>&2
}

if [[ "$1" == "help" ]]
then
    usage
    exit 0
fi

if [[ $# -ne 1 ]]
then
    usage
    echo "Strictly 1 arguments must be given."
    exit 1
fi

case $1 in
    "full")
        backup_type="full"
        ;;

    "incremental")
        backup_type="incremental"
        ;;

    *)
        usage
        echo "Backup type is incorrect."
        exit 1
        ;;
esac
shift

### FUNCTIONS ###

check_mariadb_up()
{
    if mysqladmin status &> /dev/null
    then
        echo "MariaDB is up and reachable."
    else
        echo "MariaDB is down or unreachable."
        exit 1
    fi
}

create_lock()
{
    # define lock file
    local lock_file=/var/lock/mariabackup
    local lock_fd=100

    # create lock file with flock
    eval "exec $lock_fd>\"$lock_file\""
    if ! flock -xn "$lock_fd"
    then
        echo "Cannot create lock file \"$lock_file\". Is another backup job running?"
        exit 1
    fi

    # create a trap that removes the lock file at script exit
    trap "rm -f \"$lock_file\"" EXIT
}

file_date()
{
    echo $(date +%Y-%m-%dT%H-%M-%S) # ISO 8601
}

safe_touch()
{
    # create file if not present
    if [[ ! -f "$1" ]]
    then
        echo "Create file \"$1\"."
        touch "$1"
    fi

    # check file exists and is writable
    if [[ ! -f "$1" || ! -w "$1" ]]
    then
        echo "File \"$1\" does not exist or is not writable."
        exit 1
    fi
}

safe_mkdir()
{
    # create directory if not present
    if [[ ! -d "$1" ]]
    then
        echo "Create directory \"$1\"."
        mkdir -p "$1"
    fi

    # check directory exists and is writable
    if [[ ! -d "$1" || ! -w "$1" ]]
    then
        echo "Directory \"$1\" does not exist or is not writable."
        exit 1
    fi
}

rmdir()
{
    echo -n "Remove directory \"$1\"... "
    rm -r "$1"
    echo "Done."
}

compress()
{
    echo -n "Compressing file \"$1\"... "
    gzip "$1"
    echo "Done."
}

### BEGIN OF SCRIPT ###

# print start message
echo "--------------------"
echo "MariaDB backup info:"
echo "o Backup type: $backup_type"
echo "o Hostname: $HOSTNAME"
echo "o Start datetime: $(date)"
echo "---"

# check if the MariaDB instance is up and running
check_mariadb_up

# create a lock to prevent multiple executions of the backup job at the same time
create_lock

# define "current base backup" file
# this file stores the directory name of the current backup
# it is used by the script when it performs incremental backup operations
current_base_backup_file="$BACKUP_DIR/current"

# perform backup operation
if [[ "$backup_type" == "full" ]]
then
    echo "Perform full backup of the MariaDB instance."

    # generate current_base_backup value and ensure that the file is present
    current_base_backup="$(file_date)"
    safe_touch "$current_base_backup_file"

    # define backup base directory
    base_backup_dir="$BACKUP_DIR/$current_base_backup"

    # define and create full backup directory
    full_backup_dir="$base_backup_dir/full"
    echo "Backup files are going to be written in \"$full_backup_dir\"."
    safe_mkdir "$full_backup_dir"

    # perform full backup operation
    if mariabackup --backup \
        --extra-lsndir="$full_backup_dir" \
        --stream=xbstream > "$full_backup_dir/backup.xbstream"
    then
        echo "The full backup operation has succeeded."
        compress "$full_backup_dir/backup.xbstream"

        # write new current_base_backup value in the file for future backup operations
        echo "$current_base_backup" > "$current_base_backup_file"
        echo "Value in \"$current_base_backup_file\" has been set to \"$current_base_backup\"."
    else
        echo "The full backup operation has failed."
        rmdir "$base_backup_dir"
    fi
elif [[ "$backup_type" == "incremental" ]]
then
    echo "Perform incremental backup of the MariaDB instance."

    # Get current_base_backup value from the file
    if [[ -f "$current_base_backup_file" ]]
    then
        current_base_backup=$(<"$current_base_backup_file")
    else
        echo "Cannot get the current full backup because \"current\" file does not exist."
        exit 1
    fi

    # define base backup directory
    base_backup_dir="$BACKUP_DIR/$current_base_backup"

    # define full backup directory and check if it exists
    full_backup_dir="$base_backup_dir/full"
    if [[ ! -d "$full_backup_dir" ]]
    then
        echo "Full backup directory does not exist \"$full_backup_dir\"."
        exit 1
    fi

    # define "current incremental backup" file
    # this file stores the directory name of the current incremental backup
    # it is used by the script when it performs incremental backup operations
    current_incremental_backup_file="$base_backup_dir/current_incremental"

    if [[ -f "$current_incremental_backup_file" ]]
    then
        incremental_backup_basedir="$base_backup_dir/$(<"$current_incremental_backup_file")"
    else
        incremental_backup_basedir="$full_backup_dir"
    fi

    # generate current_incremental_backup value and ensure that the file is present
    current_incremental_backup="incr_$(file_date)"
    safe_touch "$current_incremental_backup_file"

    # define and create incremental backup directory
    incremental_backup_dir="$base_backup_dir/$current_incremental_backup"
    echo "Backup files are going to be written in \"$incremental_backup_dir\"."
    safe_mkdir "$incremental_backup_dir"

    # perform incremental backup operation
    if mariabackup --backup \
        --extra-lsndir="$incremental_backup_dir" \
        --incremental-basedir=$incremental_backup_basedir \
        --stream=xbstream > "$incremental_backup_dir/backup.xbstream"
    then
        echo "The incremental backup operation has succeeded."
        compress "$incremental_backup_dir/backup.xbstream"

        # write new current_incremental_backup value in the file for future backup operations
        echo "$current_incremental_backup" > "$current_incremental_backup_file"
        echo "Value in \"$current_incremental_backup_file\" has been set to \"$current_incremental_backup\"."
    else
        echo "The incremental backup operation has failed."
        rmdir "$incremental_backup_dir"
    fi
fi
