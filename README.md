# projector-backup

# Full Backup

1. Start mysql:

```shell
docker-compose -f docker-compose-full-backup.yml up -d
```

2. Login do mysql container
3. Login to mysql and execute scripts for [table creation](./data/create.sql) and insertions:
   [insertion1](./data/insert1.sql), [insertion2](./data/insert2.sql), [insertion3](./data/insert3.sql)
4. Run:

```shell
mysqldump -u root -ppassword my_db books --flush-logs > ./backup/full.sql
```

5. Check [full back file](./backups/full/full.sql). Size: (7.4 Mb) for 300k rows
6. Delete container volume with db
7. Restore db:

- start up container
- login to container
- switch to my_db
- restore db: mysql -u root -ppassword my_db < /backup/full.sql. Speed of rollback: 1.835s

# Differential Backup

1. Start mysql:

```shell
docker-compose -f docker-compose-diff-backup.yml up -d
```

2. Run script [create table](./data/create.sql) and [insert data](./data/insert1.sql)
3. Check how many log-bin files created:

```shell
total 5.2M
-rw-r----- 1 mysql mysql  180 Sep 21 14:45 log-bin.000001
-rw-r----- 1 root  root  2.9M Sep 21 14:45 log-bin.000002
-rw-r----- 1 root  root   950 Sep 21 14:45 log-bin.000003
-rw-r----- 1 root  root  2.1M Sep 21 14:45 log-bin.000004
-rw-r----- 1 root  root   157 Sep 21 14:45 log-bin.000005
-rw-r----- 1 root  root   115 Sep 21 14:45 log-bin.index
```

4. Make full backup:

```shell
mysqldump -u root -ppassword my_db books --flush-logs > /backup/full.sql
```

5. Run script [insert data 2](./data/insert2.sql) and [insert data 3](./data/insert3.sql)
6. Check how many log-bin files created:

```shell
root@fa1603c08b34:/# ls /backup/ -lh
total 14M
-rw-r--r-- 1 root  root  2.4M Sep 21 14:29 full.sql
-rw-r----- 1 mysql mysql  180 Sep 21 14:28 log-bin.000001
-rw-r----- 1 root  root  2.9M Sep 21 14:28 log-bin.000002
-rw-r----- 1 root  root   951 Sep 21 14:28 log-bin.000003
-rw-r----- 1 root  root  2.1M Sep 21 14:28 log-bin.000004
-rw-r----- 1 root  root   202 Sep 21 14:29 log-bin.000005
-rw-r----- 1 root  root   180 Sep 21 14:36 log-bin.000006
-rw-r----- 1 root  root  2.2M Sep 21 14:38 log-bin.000007
-rw-r----- 1 root  root  2.2M Sep 21 14:38 log-bin.000008
-rw-r----- 1 root  root   157 Sep 21 14:38 log-bin.000009
-rw-r----- 1 root  root   207 Sep 21 14:38 log-bin.index
```

7. Make diff backup by choosing bin-log files:

```shell
mysqlbinlog /backup/log-bin.000007 /backup/log-bin.000008 /backup/log-bin.000009 > /backup/diff-backup.sql
```

8. Delete table and run backup: full backup from full.sql file and each diff backup created before:

```shell
mysql -u root -ppassword my_db < /backup/full.sql
```

You will see there are 99999 rows in the table restored (as it was made during insert1). Time: 0.740s

```shell
mysql -u root -ppassword my_db < /backup/diff-backup.sql
```

Additional data added as it was made during insert2 and insert3. Time: 0.460s

# Incremental Backup

Almost the same as Differential, except `mysqlbinlog` is run for each bin-log file for small data changes backup
creation

1. Make a full back up.
2. When new bin-log file(s) is created, make a backup to new sql file.
3. When data is needed to be restored, restore full back up and after that restore each incremental back up.

```shell
mysqldump -u root -ppassword my_db books --flush-logs > /backup/full.sql
mysqlbinlog /backup/log-bin.000007 > /backup/incr-1.sql
mysqlbinlog /backup/log-bin.000008 > /backup/incr-2.sql
```

# Reverse Delta Backup

It starts from full backup and log-bin files backup. Next time, it will not be a delta because no changes were made after
initial backup. When new changes are made, new full back up is made and rollback diff between 2 backups are calculated that will be 
run next time in order to restore to previous state. The first full back up can be removed. Next time if e need to restore to
previous state, we need to apply rollback backup against full backup. During the time fullback backup increases in size.
The most difficult part is to prepare a script that can create rollback backup and apply to the latest full backup in order
to restore previous state.


# CDP

One of possible implementations might be:
1. Enable bin log as we did above for incremental and differential backup.
2. Using mysqldump tool to frequently make dumps (will not be suited for large dbs)

# Comparison Tables

| Backup Type   | Size                                                                                                                                                                                                    | Ability to update at specific time point                                                                                                | Speed of rollback                                                             | Cost                                                                                          |
|---------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Full          | Takes the most storage size                                                                                                                                                                             | No                                                                                                                                      | The lowest                                                                    | The simplest from implementation, storage cost depends on db size                             |
| Incremental   | Efficient in terms of storage                                                                                                                                                                           | Yes                                                                                                                                     | Fast                                                                          | Simple, requires additional steps to make a backup for specific bin log                       |
| Differential  | More storage-efficient than full backups but less than incremental backups. Each differential backup will typically be larger than the last, as it includes all data changed since the last full backup | Yes, Easier and faster to restore from than incremental backups, as you only need the last full backup and the last differential backup | Fast, depends on differences between backups                                  | Simple, requires additional steps to make a backup for specific bin log(s)                    |
| Reverse Delta | Tend to be more storage-efficient then differential, as it keeps one full backup of the most current state and smaller sets of changes to revert to older states                                        | Yes                                                                                                                                     | Restoring to older states requires applying several deltas, which can be slow | Complex to implement                                                                          |
| CDP           | High storage size (especially for the solution when using mysqldump for each new bin log)                                                                                                               | Yes, can restore data to any point in time                                                                                              |                                                                               | Complex to set up and manage, require more computational resources and can impact performance |

