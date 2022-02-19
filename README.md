# Mariabackup scripts

## Description

Mariabackup is an open source tool provided by MariaDB for performing physical online backups.

See ["Mariabackup" documentation](https://mariadb.com/kb/en/mariabackup/) on MariaDB Knowledge Base Website.

This tutorial will walk you through the steps of using Mariabackup for a MariaDB on Red Hat family distributions of Linux.

---

## Content

- [Installation](#installation)
- [Full Backup and Restore](#full-backup-and-restore)
- [Partial Backup and Restore](#partial-backup-and-restore)
- [Incremental Backup and Restore](#incremental-backup-and-restore)
- [Backup with automation scripts](#backup-with-automation-scripts)

## Installation

Mariabackup is present in an additional MariaDB package.

To install the package, run:

```sh
sudo yum install -y MariaDB-backup
```

Mariabackup requires privileges on the MariaDB instance to perform backup operations.

To create a user for Mariabackup, run:

```sh
sudo mysql --execute="CREATE USER 'mariabackup'@'localhost' IDENTIFIED BY '<secret>'"
```

To grant the required privileges to the user, run:

```sh
sudo mysql --execute="GRANT RELOAD, PROCESS, LOCK TABLES, BINLOG MONITOR ON *.* TO 'mariabackup'@'localhost'"
```

Create an option file for Mariabackup:

```sh
sudo tee /etc/my.cnf.d/mariabackup.cnf << EOF
[mariabackup]
user=mariabackup
password=<secret>
EOF

sudo chmod 640 /etc/my.cnf.d/mariabackup.cnf
```

_This will be automatically used by Mariabackup to get the user credentials._

## Full Backup and Restore

The following steps follow this documentation: ["Full Backup and Restore with Mariabackup" on MariaDB Knowledge Base Website](https://mariadb.com/kb/en/full-backup-and-restore-with-mariabackup/).

### Perform Backup

First of all, you need to create the directory where the backup files will be stored.
Run:

```sh
sudo mkdir -p /var/lib/mariabackup/backup
```

To perform a full backup of the MariaDB instance, run:

```sh
sudo mariabackup --backup --target-dir /var/lib/mariabackup/backup
```

### Restore from backup

In order to restore backup files, you need first to prepare them.
Run:

```sh
sudo mariabackup --prepare --target-dir /var/lib/mariabackup/backup
```

If no error has been encountered during the preparation, then you can proceed to the following steps:

- Stop the MariaDB service.

    ```sh
    sudo systemctl stop mariadb
    ```

- Remove the files from the MariaDB data directory.

    ```sh
    sudo rm -fr /var/lib/mysql/*
    ```

- Run the MariaDB "Copy back" operation.

    ```sh
    sudo mariabackup --copy-back --target-dir /var/lib/mariabackup/backup
    ```

- Fix the file permissions.

    ```sh
    sudo chown -R mysql:mysql /var/lib/mysql
    ```

- Start the MariaDB service.

    ```sh
    sudo systemctl start mariadb
    ```

## Partial Backup and Restore

Related documentation: ["Partial Backup and Restore with Mariabackup" on MariaDB Knowledge Base Website](https://mariadb.com/kb/en/partial-backup-and-restore-with-mariabackup/).

The steps are almost similar to the full backup and restore ones.

The only difference is that you need to specify some options when you perform the full backup, like so:

```sh
sudo mariabackup --backup --target-dir /var/lib/mariabackup/backup --databases="db_nameX db_nameY" --tables="tab_*"
```

_More options are mentioned in the documentation._

## Incremental Backup and Restore

Follow this documentation: ["Incremental Backup and Restore with Mariabackup" on MariaDB Knowledge Base Website](https://mariadb.com/kb/en/incremental-backup-and-restore-with-mariabackup/).

## Backup with automation scripts

### Backup script

[backup.sh](./backup.sh)

_Before all, read the script and ensure that the global variables set in the script match your environment (top of the script). If not, edit the variable values._

Usage:

```sh
./backup.sh {full|incremental}
```

- The unique argument defines the type of backup to perform on the MariaDB instance with Mariabackup.

### Restore script

[restore.sh](./restore.sh)

_Before all, read the script and ensure that the global variables set in the script match your environment (top of the script). If not, edit the variable values._

Usage:

```sh
./restore.sh <backup_dirname> {full|<incremental_backup_dirname>}
```

- The first argument of the script defines the base directory of the target backup.
- The second argument defines the target backup directory to restore in MariaDB instance with Mariabackup. It can be the full backup or any incremental backup.

### Example: Incremental backup with Cron

#### Create the backup job

In this example, we use Cron jobs to schedule the backup script executions.

Consider that we use the following environment setup:

| Description | Path |
|---|---|
| MariaDB data directory | /var/lib/mysql |
| Mariabackup backup directory | /var/lib/mariabackup/backup |
| Mariabackup backup script | /var/lib/mariabackup/bin/backup.sh |
| Mariabackup restore script | /var/lib/mariabackup/bin/restore.sh |
| Mariabackup log directory | /var/lib/mariabackup/log |
| Mariabackup prepare directory | /var/lib/mariabackup/prepare |

For example, let's take this scenario:

- Perform a full backup at 00:00 (midnight)
- Perform incremental backup every hour from 01:00 to 11:00
- Perform a full backup at 00:00 (noon)
- Perform incremental backup every hour from 13:00 to 23:00

Translated to Crontab, it results to the following entries:

```sh
0 0,12 * * *        /var/lib/mariabackup/bin/backup.sh full        &> "/var/lib/mariabackup/log/full_$(date +\%Y-\%m-\%dT\%H-\%M-\%S).log"
0 1-11,13-23 * * *  /var/lib/mariabackup/bin/backup.sh incremental &> "/var/lib/mariabackup/log/incr_$(date +\%Y-\%m-\%dT\%H-\%M-\%S).log"
```

To create the backup job, edit the root user's crontab, add the entries above, save it and Voilà!

As the backup job is operational, it generates the following backup directory structure every day:

```txt
/var/lib/mariabackup/backup
│
├── 2021-01-01T00-00-01             -> base backup created at 00:00
│   ├── full                        -> full backup performed at 00:00
│   ├── incr_2021-01-01T01-00-01    -> incremental backup performed at 01:00
│   ├── incr_2021-01-01T02-00-01    -> incremental backup performed at 02:00
│   ├── incr_2021-01-01T03-00-01    -> incremental backup performed at 03:00
│   ├── incr_2021-01-01T04-00-01    -> incremental backup performed at 04:00
│   ├── incr_2021-01-01T05-00-01    -> incremental backup performed at 05:00
│   ├── incr_2021-01-01T06-00-01    -> incremental backup performed at 06:00
│   ├── incr_2021-01-01T07-00-01    -> incremental backup performed at 07:00
│   ├── incr_2021-01-01T08-00-01    -> incremental backup performed at 08:00
│   ├── incr_2021-01-01T09-00-01    -> incremental backup performed at 09:00
│   ├── incr_2021-01-01T10-00-01    -> incremental backup performed at 10:00
│   └── incr_2021-01-01T11-00-01    -> incremental backup performed at 11:00
│
└── 2021-01-01T12-00-01             -> base backup created at 12:00
    ├── full                        -> full backup performed at 12:00
    ├── incr_2021-01-01T13-00-01    -> incremental backup performed at 13:00
    ├── incr_2021-01-01T14-00-01    -> incremental backup performed at 14:00
    ├── incr_2021-01-01T15-00-01    -> incremental backup performed at 15:00
    ├── incr_2021-01-01T16-00-01    -> incremental backup performed at 16:00
    ├── incr_2021-01-01T17-00-01    -> incremental backup performed at 17:00
    ├── incr_2021-01-01T18-00-01    -> incremental backup performed at 18:00
    ├── incr_2021-01-01T19-00-01    -> incremental backup performed at 19:00
    ├── incr_2021-01-01T20-00-01    -> incremental backup performed at 20:00
    ├── incr_2021-01-01T21-00-01    -> incremental backup performed at 21:00
    ├── incr_2021-01-01T22-00-01    -> incremental backup performed at 22:00
    └── incr_2021-01-01T23-00-01    -> incremental backup performed at 23:00
```

_The script does not remove the old backup files. Consider adding a clean up job on your system if required._

#### Restore from a backup

For the example, let's consider that it is 09:30 and we need to restore the MariaDB instance as it was at 4:00.

We have the following backup directory structure:

```txt

/var/lib/mariabackup/backup
│
└── 2021-01-01T00-00-01             -> base backup of the target backup
    ├── full
    ├── incr_2021-01-01T01-00-01
    ├── incr_2021-01-01T02-00-01
    ├── incr_2021-01-01T03-00-01
    ├── incr_2021-01-01T04-00-01    -> target backup to restore
    ├── incr_2021-01-01T05-00-01
    ├── incr_2021-01-01T06-00-01
    ├── incr_2021-01-01T07-00-01
    ├── incr_2021-01-01T08-00-01
    └── incr_2021-01-01T09-00-01
```

To restore the MariaDB instance, we perform the following actions:

- Stop the MariaDB service.

    ```sh
    sudo systemctl stop mariadb
    ```

- Backup the MariaDB data directory.

    ```sh
    sudo cp -R /var/lib/mysql /var/lib/mysql_save
    ```

- Remove all the file in the data directory.

    ```sh
    sudo rm -fr /var/lib/mysql/*
    ```

- Execute the restore script.

    ```sh
    sudo /var/lib/mariabackup/bin/restore.sh 2021-01-01T00-00-01 incr_2021-01-01T04-00-01
    ```

- Change the ownership of the data directory.

    ```sh
    sudo chown -R mysql:mysql /var/lib/mysql
    ```

- Start the MariaDB service.

    ```sh
    sudo systemctl start mariadb
    ```
