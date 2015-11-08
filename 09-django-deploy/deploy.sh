#!/bin/bash
##############################################################
# Title		 :
# Author     : Artyom Demyanov
# Date       : 11/08/2015
# Last Edited: 11/09/2015, Artyom Demyanov
# Description:

# 1. Create and login new user for deployment with adduser command  (optional)
# 2. Clone your repository to your machine
# 3. Add static root to your settings file:
# STATIC_ROOT = os.path.join(BASE_DIR, 'static/')
#
# Remember that you can store your global static files in your mysite/mysite directory:
# STATICFILES_DIRS = [os.path.join(BASE_DIR, os.path.basename(BASE_DIR) + '/static')]
# 4. Configure your databse
# 5. Put this script into the root directory of your local repository
# 6. Run it from any directory you want

##############################################################

VERSION=1.0
SUBJECT=deployment
USAGE="usage: deploy [-cvh]
  -c, --clean   : clean deployment directories
  -v, --version : display version information about the current instance of script
  -h, --help    : print this help message"

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
PROJ=${DIR##*/}

while test $# -gt 0; do
	case $1 in
		-c|--clean)
		  # remove deployment directory
		  echo -e "\e[33mRemoving deployment directory\e[0m"
		  rm -rf $DIR/deployment

		  # remove static directory
		  echo -e "\e[33mRemoving static directory\e[0m"
		  rm -rf $DIR/static

		  # remove media directory
		  echo -e "\e[33mRemoving media directory\e[0m"
		  rm -rf $DIR/media

		  # # remove venv directory
		  # (If you want to remove virtualenv directory with --clean option uncomment this lines)
		  # echo -e "\e[33mRemoving virtualenv directory\e[0m"
		  # rm -rf $DIR/venv

		  # remove symbolic link
		  echo -e "\e[33mRemoving nginx symbolic link\e[0m"
		  sudo rm -f /etc/nginx/sites-enabled/${PROJ}_nginx.conf
		  exit
		  ;;
		-v|--version)
		  echo "$VERSION"
		  exit
		  ;;
		-h|--help|*)
		  echo "$USAGE"
		  exit
		  ;;
esac
shift
done

LOCK_FILE=/tmp/$SUBJECT.lock
if [ -f $LOCK_FILE ]; then
	echo -e "\e[31mError: Script is already running. Could not get lock\e[0m" $LOCK_FILE >> /dev/stderr
	exit 1
fi

trap "rm -f $LOCK_FILE" EXIT
touch $LOCK_FILE

echo "Please enter your machine's IP address or FQDN:"
read DOMAIN
echo

function install {
	for package in "$@"
	do
		if [ $(dpkg-query -W -f='${Status}' $package 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
			echo -e "\e[33mInstalling $package\e[0m"
        		sudo apt-get install -y "$package"
		else
			echo -e "\e[33m$package already installed\e[0m"
    		fi
	done
}

# install package for managing ppa
install software-properties-common

# add nginx ppa
nginx=stable
if ! grep -q nginx/$nginx /etc/apt/sources.list /etc/apt/sources.list.d/*; then
	sudo add-apt-repository ppa:nginx/$nginx
	sudo apt-get update
fi

# install nginx, tmux, python3-dev, python3-setuptools
install nginx tmux python3-dev python3-setuptools
echo

# install virtualenv
sudo easy_install-3.4 virtualenv

# create virtualenv
if ! [ -d venv ]; then
	virtualenv $DIR/venv
fi
source $DIR/venv/bin/activate

# install requirements
if [ -f $DIR/requirements.txt ]; then
	pip install -r requirements.txt
	pip install uwsgi
fi

# create deployment directory
if ! [ -d $DIR/deployment ]; then
	mkdir $DIR/deployment
fi

# create media directory
if ! [ -d $DIR/media ]; then
	mkdir $DIR/media
fi

# create static directory
if ! [ -d $DIR/static ]; then
	mkdir $DIR/static
fi

curl -o $DIR/deployment/uwsgi_params https://raw.githubusercontent.com/nginx/nginx/master/conf/uwsgi_params
cat <<EOF > $DIR/deployment/${PROJ}_nginx.conf
# $PROJ_nginx.conf

upstream django {
    server unix://$DIR/deployment/$PROJ.sock; # for a file socket
    # server 127.0.0.1:8001; # for a web port socket
}

# configuration of the server
server {
    # the port your site will be served on
    listen 80;
    # the domain name it will serve for
    server_name $DOMAIN; # substitute your machine"s IP address or FQDN
    # serven name $DOMAIN www.$DOMAIN
    charset     utf-8;

    # max upload size
    client_max_body_size 75M;

    # Django media
    location /media {
	alias $DIR/media;
    }

    # Django static
    location /static {
 	alias $DIR/static;
    }

    # Django server
    location / {
 	uwsgi_pass  django;
 	include     $DIR/deployment/uwsgi_params;
    }
}
EOF

# remove default nginx config
if [ -f /etc/nginx/sites-enabled/default ]; then
	sudo rm -f /etc/nginx/sites-enabled/default
fi

# create symbolic link
if ! [ -f /etc/nginx/sites-enabled/${PROJ}_nginx.conf ]; then
	sudo ln -s $DIR/deployment/${PROJ}_nginx.conf /etc/nginx/sites-enabled/
fi

python $DIR/manage.py collectstatic --noinput
sudo service nginx restart
cat <<EOF > $DIR/deployment/${PROJ}_uwsgi.ini
# $PROJ_uwsgi.ini
[uwsgi]

# Django-related settings
# the base directory
chdir		= $DIR

# Django's wsgi file
module		= $PROJ.wsgi

# the virtualenv
home		= $DIR/venv

# process-related settings
# master
master		= true

# maximum number of worker processes
processes       = 10

# the socket
socket		= $DIR/deployment/$PROJ.sock

# permissions
chmod-socket    = 666

# clear environment on exit
vacuum          = true
EOF

echo -e "\e[33m
To start uwsgi run following commands:

source $DIR/venv/bin/activate
tmux
uwsgi --ini $DIR/deployment/${PROJ}_uwsgi.ini

Also you can configure uwsgi to startup when the system boots
See: http://uwsgi-docs.readthedocs.org/en/latest/tutorials/Django_and_nginx.html\e[0m
"
