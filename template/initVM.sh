echo "apt 프로세스 kill"
sudo killall apt apt-get

echo "dpkg frontend lock 제거"
sudo rm /var/lib/apt/lists/lock
sudo rm /var/cache/apt/archives/lock
sudo rm /var/lib/dpkg/lock*
sudo dpkg --configure -a

echo "SET TIMEZONE"
echo "timedatectl set-timezone 'Asia/Seoul'"
timedatectl set-timezone 'Asia/Seoul'

echo "apt-get Archive SERVER CHANGE"
sed -i.bak -r 's/([a-z]{2}.)?(archive|security).ubuntu.com/mirror.kakao.com/g' /etc/apt/sources.list

echo "apt-get update / apt upgrade"
sudo apt-get update
sudo apt-get upgrade
