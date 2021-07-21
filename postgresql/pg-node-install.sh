#!/usr/bin/env bash

#------------------------------------------------------------------------------
# [ 실행전 TODO, 꼭 확인할 것 ]
# 1. DB 전용 Volume을 추가 작업을 사전에 해서 /postgresql/main 에 마운트
# 2. /etc/hosts에 적용할 IP주소 수정
# 3. ssh public key값 수정
# 4. vCore, Memory, Disk Type에 따른 성능 튜닝 values 수정
# 5. virtual IP(__VIP__) 값 수정
#------------------------------------------------------------------------------

if [ -z "$1" ] || [ -z "$2" ] ; then
	echo ">>>>> usage	: postgresql.sh <MS app 계정> <node 번호>"
	echo ">>>>> example	: postgresql.sh projection 1"
	exit
fi

__USER__=$1
__NODE_NO__=$2


__VIP__="172.27.0.21"
__SSH_PRIVATE_KEY__="-----BEGIN RSA PRIVATE KEY-----
MIICXQIBAAKBgQCq5PYmI5OgpvZRmST1NPCZbBhHMJ9ZC0AyDMs4tt8+ue+tKyAs
9O2Iwm+TmmrYT0Zl8MFd8T5xOf/0F0xWLbPc3RXqq32XwU0ubZ+cyOYwa4zOIHB0
Q6AEvjnBqoOeYiBnN0+5QL+uNVg5hw2vnwrfownkzY3ggjTtg5+5lWu96QIDAQAB
AoGAc3rxEuirk73/aThxjvlNNH+lEEY9B7DgmnGmyhZZWUvQOFaSEY8ZDHdHapjI
Zo97ZNuB73db2Kt22Hz96qZLiXJjt5Jbnpuv65T4lbNCO2qhIM1YPjdVaRkbbW2s
JXCncwhWdKFH8tXM7U9fq+iLG6K0KLr2CMbUZRL1OiGj82ECQQDkK+FkXoJ1DWPZ
dxm97l9ryePvN09P7388AKvYpEG5FHXxD7WFh9OceNffaLuAt39/TfniUKKzt2m1
LCjEt0qVAkEAv7y9V+PNokXsST2YfWPIXpJfX8BGPTWfkI5Mw4/rHO5e5irxxz0O
RvlsJpSw7GYC3WKfQX43jAeXTWo6v6DlBQJAQ66AfTVLnU0LgUZC7IP46hBI/Hx7
mkqAg1vvnaObmzrmgUsXnTRdINz3q911QQktWKXYqbkhig2t3X/r1+5GwQJBAJhC
Pi3sNeC2HCQxKMXyFiybmedEncJ/sb2ucuEdiXxJAs1Orv8jyhGsgijFDRY9D+tU
JNlybJPjd1A/mnWQRC0CQQCH0O9rmND4OvYH+8oQM8x5d6iisvWvG84sCrmAigYV
2T8LvGrygH22YAHK+fgJJDO71UYz17DmwGWaajfaE4do
-----END RSA PRIVATE KEY-----"


__PG_HOME__="/var/lib/postgresql"
__PG_BIN__="/usr/lib/postgresql/11/bin"
__PG_CONF__="/etc/postgresql/11/main"
__PG_LOG__="/var/log/postgresql/postgresql-11-main.log"

echo -n 'postgresql node 설정입니다.'
echo -n 'DB 전용 DISK 마운트는 했나요? 했다면 엔터. 안했다면 ctrl-c.'
read
cd ~

#------------------------------------------------------------------------------
# postgresql-11.12 리포지토리 및 사이닝키 추가후 설치
# postgresql-11.12, pgpool-4.1.4(extend포함), arping
#------------------------------------------------------------------------------
echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt update -y
apt install postgresql-11 -y
sleep 5
apt install pgpool2 -y
apt install postgresql-11-pgpool2 -y
apt install iputils-arping -y 


#------------------------------------------------------------------------------
# /etc/hosts 설정
#-----------------------------------------------------------------------------
cat >> /etc/hosts << EOF
# Postgresql DB cluster
172.27.1.27       pg-1
172.27.0.32       pg-2
172.27.0.110      pg-3
$__VIP__          pg-vip
EOF


#------------------------------------------------------------------------------
# OS 사용자 생성 - ms app계정, replica (복제전용계정), postgres sudoer
#------------------------------------------------------------------------------
useradd -s /bin/bash -d /home/$__USER__ -m $__USER__
#useradd -s /bin/bash -d /home/replica -m replica # 삭제해도 되지 않을까?
#useradd -s /bin/bash -d /home/pgpool -m pgpool	 # 삭제해도 되지 않을까?
echo "postgres ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/postgres



#------------------------------------------------------------------------------
# postgresql 부팅시 자동 실행 제거 및 start, stop 전용 스크립트 제공
#------------------------------------------------------------------------------
systemctl disable postgresql
systemctl disable pgpool2
systemctl daemon-reload

cat > $__PG_HOME__/start-pg.sh << EOF
$__PG_BIN__/pg_ctl start -D $__PG_CONF__ -l $__PG_LOG__
EOF

cat > $__PG_HOME__/stop-pg.sh << EOF
$__PG_BIN__/pg_ctl stop -D $__PG_CONF__ -m fast
EOF
chmod 700 $__PG_HOME__/*.sh
chown postgres:postgres $__PG_HOME__/*.sh



#------------------------------------------------------------------------------
# ssh 키 sharing : root -> postgres, postgres <-> postgres
#------------------------------------------------------------------------------
cat > .ssh/ssh_private_key << EOF
${__SSH_PRIVATE_KEY__}
EOF
chmod 600 .ssh/*

cp -R .ssh $__PG_HOME__
chown -R postgres:postgres $__PG_HOME__/.ssh
chmod 600 $__PG_HOME__/.ssh/*
chmod 700 $__PG_HOME__/.ssh



#------------------------------------------------------------------------------
# .pgpass for postgres : PG 명령어들을 interactive 없이 바로 실행할 수 있도록...
#------------------------------------------------------------------------------
cat > $__PG_HOME__/.pgpass << EOF
pg-1:5432:replication:replica:imdb21**
pg-2:5432:replication:replica:imdb21**
pg-3:5432:replication:replica:imdb21**
pg-1:5432:postgres:postgres:imdb21**
pg-2:5432:postgres:postgres:imdb21**
pg-3:5432:postgres:postgres:imdb21**
EOF

chmod 600 $__PG_HOME__/.pgpass
chown postgres:postgres $__PG_HOME__/.pgpass


#------------------------------------------------------------------------------
# DB 사용자 및 테이블 생성은 다음 절차를 따른다. : 참고 OS와 DB사용자를 일치시켜라!!!'
#------------------------------------------------------------------------------
chmod 755 /root # WARN제거: could not change directory to "/root": Permission denied

sudo -u postgres createuser replica --replication  --login
sudo -u postgres psql -c "alter user replica with password 'imdb21**';"

sudo -u postgres createuser pgpool --login
sudo -u postgres psql -c "alter user pgpool with password 'imdb21**';"
sudo -u postgres psql -c "grant pg_monitor to pgpool;"

sudo -u postgres createuser $__USER__
sudo -u postgres psql -c "alter user $__USER__ with password 'imdb21**';"

sudo -u postgres psql -c "alter user postgres with password 'imdb21**';"

sudo -u postgres createdb db_projection -O $__USER__
sudo -u postgres createdb db_order -O $__USER__
sudo -u postgres createdb db_configuration -O $__USER__
sudo -u postgres createdb db_backupmgt -O $__USER__
sudo -u postgres createdb db_servermgt -O $__USER__
sudo -u postgres createdb db_admin -O $__USER__
sudo -u postgres createdb db_monitoring -O $__USER__

#------------------------------------------------------------------------------
# 서버 중지
#------------------------------------------------------------------------------
systemctl stop pgpool2
systemctl stop postgresql


#------------------------------------------------------------------------------
# db 저장소 변경 - 사전 /postgresql에 disk가 마운트 되어 있어야 한다.
#------------------------------------------------------------------------------
mkdir -p /postgresql/archive
mv /var/lib/postgresql/11/main /postgresql
chown -R postgres:postgres /postgresql
sed -i.bak -r "s#data_directory = '/var/lib/postgresql/11/main'#data_directory = '/postgresql/main'#g" $__PG_CONF__/postgresql.conf



#------------------------------------------------------------------------------
# 성능 튜닝
#------------------------------------------------------------------------------
# [shared_buffers] 총메모리의 25% 수준: 2GB는 512MB
sed -i.bak -r "s/shared_buffers = 128MB/shared_buffers = 256MB/g" $__PG_CONF__/postgresql.conf

# [effective_cache_size] 총메모리의 50% 수준: 2GB는 1GB
sed -i.bak -r "s/#effective_cache_size = 4GB/effective_cache_size = 768MB/g" $__PG_CONF__/postgresql.conf

# [maintenance_work_mem] 총메모리GB x 50MB = 2GB x 50MB = 100MB
sed -i.bak -r "s/#maintenance_work_mem = 64MB/maintenance_work_mem = 64MB/g" $__PG_CONF__/postgresql.conf

# [checkpoint_completion_target]
sed -i.bak -r "s/#checkpoint_completion_target = 0.5/checkpoint_completion_target = 0.9/g" $__PG_CONF__/postgresql.conf

# [wal_buffers] shared_buffers의 1/32 수준이나, -1로 설정하면 shared_buffers에 따라 자동 조정
sed -i.bak -r "s/#wal_buffers = -1/wal_buffers = 7864kB/g" $__PG_CONF__/postgresql.conf

# [default_statistics_target]
sed -i.bak -r "s/#default_statistics_target = 100/default_statistics_target = 100/g" $__PG_CONF__/postgresql.conf

# [random_page_cost] HDD or SSD에 따라 값이 달라짐
sed -i.bak -r "s/#random_page_cost = 4.0/random_page_cost = 4.0/g" $__PG_CONF__/postgresql.conf

# [effective_io_concurrency] HDD or SSD에 따라 값이 달라짐
sed -i.bak -r "s/#effective_io_concurrency = 1/effective_io_concurrency = 2/g" $__PG_CONF__/postgresql.conf

# [work_mem]
sed -i.bak -r "s/#work_mem = 4MB/work_mem = 1310kB/g" $__PG_CONF__/postgresql.conf

# [min_wal_size]
sed -i.bak -r "s/min_wal_size = 80MB/min_wal_size = 1GB/g" $__PG_CONF__/postgresql.conf

# [max_wal_size]
sed -i.bak -r "s/max_wal_size = 1GB/max_wal_size = 4GB/g" $__PG_CONF__/postgresql.conf



#------------------------------------------------------------------------------
# 스트리밍 replication 설정
#------------------------------------------------------------------------------
sed -i.bak -r "s/#wal_level = replica/wal_level = replica/g" $__PG_CONF__/postgresql.conf
sed -i.bak -r "s/#max_wal_senders = 10/max_wal_senders = 10/g" $__PG_CONF__/postgresql.conf
sed -i.bak -r "s/#wal_keep_segments = 0/wal_keep_segments = 32/g" $__PG_CONF__/postgresql.conf
sed -i.bak -r "s/#wal_log_hints = off/wal_log_hints = on/g" $__PG_CONF__/postgresql.conf
sed -i.bak -r "s/#max_replication_slots = 10/max_replication_slots = 10/g" $__PG_CONF__/postgresql.conf

sed -i.bak -r "s/#archive_mode = off/archive_mode = on/g" $__PG_CONF__/postgresql.conf
sed -i.bak -r "s/#archive_timeout = 0/archive_timeout = 120/g" $__PG_CONF__/postgresql.conf
echo "archive_command = 'cp %p /postgresql/archive/arch_%f.arc'" >> $__PG_CONF__/postgresql.conf

# pgpool 온라인 복구 모드로 시작할 수 있도록
sed -i.bak -r "s/#hot_standby = on/hot_standby = on/g" $__PG_CONF__/postgresql.conf
     
# 동기화 방식을 쓸 경우 아래 활성화. default 비동기 방식임
#sed -i.bak -r "s/#synchronous_commit = on/synchronous_commit = on/g" $__PG_CONF__/postgresql.conf
#sed -i.bak -r "s/#synchronous_standby_names = ''/synchronous_standby_names = '*'/g" $__PG_CONF__/postgresql.conf



#------------------------------------------------------------------------------
# pg_hba.conf 설정
#------------------------------------------------------------------------------
cat > $__PG_CONF__/pg_hba.conf << EOF
# "local" is for Unix domain socket connections only
local   all             all                                     trust
# IPv4 local connections:
host    all             all             127.0.0.1/32            trust
# IPv6 local connections:
host    all             all             ::1/128                 trust
# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
# same subnet
host    replication     all             172.27.0.0/16           trust
host    all             all             172.27.0.0/16           trust
EOF


sed -i.bak -r "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" $__PG_CONF__/postgresql.conf
# [변경전] 127.0.0.1:5432          0.0.0.0:*               LISTEN      24517/postgres
# [변경후] 0.0.0.0:5432            0.0.0.0:*               LISTEN      26412/postgres


#------------------------------------------------------------------------------
# pgpool 설정 파일 다운로드
#------------------------------------------------------------------------------
wget --quiet -O /etc/pgpool2/pgpool.conf https://github.com/jamesby99/dummy/raw/master/postgresql/pgpool.conf
wget --quiet -O /etc/pgpool2/failover.sh https://github.com/jamesby99/dummy/raw/master/postgresql/failover.sh
wget --quiet -O /etc/pgpool2/follow_master.sh https://github.com/jamesby99/dummy/raw/master/postgresql/follow_master.sh
wget --quiet -O /etc/pgpool2/recovery_1st_stage https://github.com/jamesby99/dummy/raw/master/postgresql/recovery_1st_stage.sh
wget --quiet -O /etc/pgpool2/pgpool_remote_start https://github.com/jamesby99/dummy/raw/master/postgresql/pgpool_remote_start.sh

chmod 755 /etc/pgpool2/*.sh
chmod 755 /etc/pgpool2/recovery_1st_stage
chmod 755 /etc/pgpool2/pgpool_remote_start

cp /etc/pgpool2/recovery_1st_stage /postgresql/main
cp /etc/pgpool2/pgpool_remote_start /postgresql/main
chown postgres:postgres /postgresql/main/recovery_1st_stage
chown postgres:postgres /postgresql/main/pgpool_remote_start



#------------------------------------------------------------------------------
# pgpool.conf 설정
#------------------------------------------------------------------------------
sed -i.bak -r "s/delegate_IP = 'delegate_IP'/delegate_IP = '$__VIP__'/g" /etc/pgpool2/pgpool.conf
sed -i.bak -r "s/wd_hostname = 'wd_hostname'/wd_hostname = 'pg-$__NODE_NO__'/g" /etc/pgpool2/pgpool.conf

if [ $__USER__  != 'orders' ]; then
	sed -i.bak -r "s/sr_check_database = 'db_order'/sr_check_database = 'db_$__USER__'/g" /etc/pgpool2/pgpool.conf
fi

if [ $__NODE_NO__ == '1' ]; then
	sed -i.bak -r "s/heartbeat_destination0 = 'pg-x'/heartbeat_destination0 = 'pg-2'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/heartbeat_destination1 = 'pg-x'/heartbeat_destination1 = 'pg-3'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/other_pgpool_hostname0 = 'pg-x'/other_pgpool_hostname0 = 'pg-2'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/other_pgpool_hostname1 = 'pg-x'/other_pgpool_hostname1 = 'pg-3'/g" /etc/pgpool2/pgpool.conf	
elif [ $__NODE_NO__ == '2' ]; then
	sed -i.bak -r "s/heartbeat_destination0 = 'pg-x'/heartbeat_destination0 = 'pg-1'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/heartbeat_destination1 = 'pg-x'/heartbeat_destination1 = 'pg-3'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/other_pgpool_hostname0 = 'pg-x'/other_pgpool_hostname0 = 'pg-1'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/other_pgpool_hostname1 = 'pg-x'/other_pgpool_hostname1 = 'pg-3'/g" /etc/pgpool2/pgpool.conf	
elif [ $__NODE_NO__ == '3' ]; then
	sed -i.bak -r "s/heartbeat_destination0 = 'pg-x'/heartbeat_destination0 = 'pg-1'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/heartbeat_destination1 = 'pg-x'/heartbeat_destination1 = 'pg-2'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/other_pgpool_hostname0 = 'pg-x'/other_pgpool_hostname0 = 'pg-1'/g" /etc/pgpool2/pgpool.conf
	sed -i.bak -r "s/other_pgpool_hostname1 = 'pg-x'/other_pgpool_hostname1 = 'pg-2'/g" /etc/pgpool2/pgpool.conf	
fi



#------------------------------------------------------------------------------
# pcp.conf
#------------------------------------------------------------------------------
echo 'pgpool:62843c0232f945e8b2261d720f2c2670' >> /etc/pgpool2/pcp.conf		# id:md5 password
echo 'localhost:9898:pgpool:imdb21**' > ~/.pcppass
chmod 600 ~/.pcppass

    
#------------------------------------------------------------------------------
# postgresql 재시작
#------------------------------------------------------------------------------
systemctl start postgresql


#------------------------------------------------------------------------------
# postgresql 재시작후 해야할 작업들
#------------------------------------------------------------------------------
#echo -e "\n" | sudo -u postgres psql -c "SELECT * FROM pg_create_physical_replication_slot('replication_slot');"	# replication_slot 생성
sudo -u postgres psql template1 -c "CREATE EXTENSION pgpool_recovery;"							# ?
chmod 700 /root													 	# sudo -u postgres가 더이상 없음으로 원복


#------------------------------------------------------------------------------
# postgresql 종료
#------------------------------------------------------------------------------
systemctl stop postgresql


echo '생성결과는 다음의 명령어로 확인하세요'
echo 'su - postgres'
echo 'psql -c "select * from pg_user;"'
echo 'psql -l'
echo 'psql -c "show data_directory;"' #변경 디렉토리 확인
