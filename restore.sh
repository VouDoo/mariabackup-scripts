#!/bin/bash
#
# restore MariaDB instance from backup with Mariabackup.

### GLOBAL VARIABLES ###

# path to the MariaDB data directory
MARIADB_DATA_DIR="/var/lib/mysql"
# path to the directory where mariabackup stores the backup files
BACKUP_DIR="/var/lib/mariabackup/backup"
# path to the directory where mariabackup prepare the data file
PREPARE_DIR="/var/lib/mariabackup/prepare"

### SCRIPT ARGUMENTS ###

usage()
{
    echo "Usage: $0 <backup_dirname> {full|<incremental_backup_dirname>}" 1>&2
}

if [[ "$1" == "help" ]]
then
    usage
    exit 0
fi

if [[ $# -ne 2 ]]
then
    usage
    echo "Strictly 2 arguments must be given."
    exit 1
fi

base_backup_dir="$BACKUP_DIR/$1"
shift

if [[ "$1" == "full" ]]
then
    restore_type="full"
    full_backup_dir="$base_backup_dir/full"
else
    restore_type="incremental"
    full_backup_dir="$base_backup_dir/full"
    incremental_backup_dir="$base_backup_dir/$1"
fi
shift

### FUNCTIONS ###

check_mariadb_down()
{
    if ! mysqladmin status &> /dev/null
    then
        echo "MariaDB is down and ready to be restored."
    else
        echo "MariaDB must be stopped."
        exit 1
    fi
}

check_mariadb_data_empty()
{
    if [[ -n "$(find "$MARIADB_DATA_DIR" -maxdepth 0 -type d -empty 2>/dev/null)" ]]
    then
        echo "MariaDB data directory \"$MARIADB_DATA_DIR\" is empty and ready to be restored."
    else
        echo "MariaDB data directory \"$MARIADB_DATA_DIR\" is not empty or is not a directory."
        exit 1
    fi
}

file_date()
{
    echo $(date +%Y-%m-%dT%H-%M-%S) # ISO 8601
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

extract_stream()
{
    echo -n "Exract stream file \"$1\" to \"$2\"... "
    if zcat "$1" | mbstream -x -C "$2/"
    then
        echo "Done."
    else
        echo "Failed to extract."
        exit 1
    fi
}

### BEGIN OF SCRIPT ###

# print start message
echo "--------------------"
echo "MariaDB restore info:"
echo "o Restore type: $restore_type"
echo "o Restore from: $target_backup_dir"
echo "o Hostname: $HOSTNAME"
echo "o Start datetime: $(date)"
echo "---"

# check if base backup directory to restore exists
if [[ ! -d "$base_backup_dir" ]]
then
    echo "Missing base backup directory \"$base_backup_dir\"."
    exit 1
fi

# check if full backup directory to restore exists
if [[ ! -d "$full_backup_dir" ]]
then
    echo "Missing full backup directory \"$full_backup_dir\"."
    exit 1
fi

# check if incremental backup directory to restore exists
if [[ ! -d "$incremental_backup_dir" && $restore_type == "incremental" ]]
then
    echo "Missing incremental backup directory \"$incremental_backup_dir\"."
    exit 1
fi

# check if the MariaDB instance is down
check_mariadb_down

# check if the MariaDB data directory is empty
check_mariadb_data_empty

# initialize mariabackup temporary directory
mariabackup_tmp_dir="$PREPARE_DIR/mariabackup_$(file_date)"
safe_mkdir "$mariabackup_tmp_dir"
trap "rm -fr \"$mariabackup_tmp_dir\"" EXIT

# define and create mariabackup target directory
mariabackup_target_dir="$mariabackup_tmp_dir/target"
echo "Backup files are going to be prepared and restored from \"$mariabackup_target_dir\"."
safe_mkdir "$mariabackup_target_dir"

# extract full backup into mariabackup target directory
extract_stream "$full_backup_dir/backup.xbstream.gz" "$mariabackup_target_dir"

# prepare full backup in mariabackup target directory
if mariabackup --prepare --target-dir="$mariabackup_target_dir"
then
    echo "Prepare operation on files from \"$full_backup_dir\" has succeeded."
else
    echo "Prepare operation on files from \"$full_backup_dir\" has failed."
    exit 1
fi

# prepare incremental backup(s) in mariabackup target directory
if [[ $restore_type == "incremental" ]]
then
    # define and create mariabackup incremental temporary directory
    mariabackup_incremental_tmp_dir="$mariabackup_tmp_dir/incr_tmp"
    safe_mkdir "$mariabackup_incremental_tmp_dir"

    for incremental_dir in $(find "$base_backup_dir" -maxdepth 1 -type d -name "incr_*" -print | sort -n)
    do
        # extract incremental backup into mariabackup incremental temporary directory
        extract_stream "$incremental_dir/backup.xbstream.gz" "$mariabackup_incremental_tmp_dir"

        # merge incremental backup into mariabackup target directory
        if mariabackup --prepare \
            --target-dir="$mariabackup_target_dir" \
            --incremental-dir="$mariabackup_incremental_tmp_dir"
        then
            echo "Prepare operation on files from \"$incremental_dir\" has succeeded."
        else
            echo "Prepare operation on files from \"$incremental_dir\" has failed."
            exit 1
        fi

        # clean up incremental temporary directory
        rm -fr "$mariabackup_incremental_tmp_dir"/*

        # stop if requested incremental backup has been merged
        if [[ "$incremental_dir" == "$incremental_backup_dir" ]]
        then
            break 2
        fi
    done
fi

# copy back files from mariabackup target directory to MariaDB data directory
if mariabackup --move-back --target-dir="$mariabackup_target_dir"
then
    echo "Copy back operation has succeeded."
else
    echo "Copy back operation has failed."
    exit 1
fi
