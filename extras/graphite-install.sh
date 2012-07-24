#!/bin/bash

###################
# PREPARE SERVER
###################
sudo apt-get update
sudo apt-get install --assume-yes git memcached monit nodejs npm python-dev python-pip python-django python-django-tagging python-twisted python-memcache sqlite3 libcairo2 libcairo2-dev python-cairo pkg-config libapache2-mod-wsgi
sudo pip install --upgrade pip


###################
# GET SOURCES
###################
mkdir graphite
cd graphite
git clone https://github.com/graphite-project/graphite-web.git
git clone https://github.com/graphite-project/carbon.git
git clone https://github.com/graphite-project/whisper.git
git clone https://github.com/graphite-project/ceres.git

###################
# INSTALL GRAPHITE
###################
pushd whisper
sudo python setup.py install
popd
pushd carbon
sudo python setup.py install
popd
pushd ceres
sudo python setup.py install
popd
pushd graphite-web
sudo python check-dependencies.py
sudo python setup.py install
popd

###################
# CONFIGURE GRAPHITE
###################
pushd /opt/graphite/conf
sudo cp carbon.conf.example carbon.conf
cat >> /tmp/storage-schemas.conf << EOF
# Schema definitions for Whisper files. Entries are scanned in order,
# and first match wins. This file is scanned for changes every 60 seconds.
#
#  [name]
#  pattern = regex
#  retentions = timePerPoint:timeToStore, timePerPoint:timeToStore, ...
#[stats]
#priority = 110
#pattern = ^stats\..*
#retentions = 10s:6h,1m:7d,10m:1y

#[default_1min_for_1day]
#pattern = .*
#retentions = 60s:1d

[default_1min_for_30days_15min_for_10years]
priority = 100
pattern = .*
retentions = 60:43200,900:350400
EOF
sudo cp /tmp/storage-schemas.conf storage-schemas.conf
sudo mkdir -p /opt/graphite/storage/log/webapp

###################
# CONFIGURE APACHE
###################
cat >> /tmp/graphite-vhost.conf << EOF
# XXX You need to set this up!
# Read http://code.google.com/p/modwsgi/wiki/ConfigurationDirectives#WSGISocketPrefix
WSGISocketPrefix /var/run/wsgi

<VirtualHost *:80>
        ServerName graphite
        DocumentRoot "/opt/graphite/webapp"
        ErrorLog /opt/graphite/storage/log/webapp/error.log
        CustomLog /opt/graphite/storage/log/webapp/access.log common

        # I've found that an equal number of processes & threads tends
        # to show the best performance for Graphite (ymmv).
        WSGIDaemonProcess graphite processes=5 threads=5 display-name='%{GROUP}' inactivity-timeout=120
        WSGIProcessGroup graphite
        WSGIApplicationGroup %{GLOBAL}
        WSGIImportScript /opt/graphite/conf/graphite.wsgi process-group=graphite application-group=%{GLOBAL}

        # XXX You will need to create this file! There is a graphite.wsgi.example
        # file in this directory that you can safely use, just copy it to graphite.wgsi
        WSGIScriptAlias / /opt/graphite/conf/graphite.wsgi 

        Alias /content/ /opt/graphite/webapp/content/
        <Location "/content/">
                SetHandler None
        </Location>

        # XXX In order for the django admin site media to work you
        # must change @DJANGO_ROOT@ to be the path to your django
        # installation, which is probably something like:
        # /usr/lib/python2.6/site-packages/django
        Alias /media/ "@DJANGO_ROOT@/contrib/admin/media/"
        <Location "/media/">
                SetHandler None
        </Location>

        # The graphite.wsgi file has to be accessible by apache. It won't
        # be visible to clients because of the DocumentRoot though.
        <Directory /opt/graphite/conf/>
                Order deny,allow
                Allow from all
        </Directory>

</VirtualHost>
EOF
sudo cp /tmp/graphite-vhost.conf /etc/apache2/sites-available/graphite
sudo cp /opt/graphite/conf/graphite.wsgi.example /opt/graphite/conf/graphite.wsgi
sudo a2enmod wsgi
sudo a2ensite graphite
sudo mkdir -p /var/run/wsgi

####################################
# INITIAL DATABASE CREATION
####################################
cd /opt/graphite/webapp/graphite/
sudo cp local_settings.py.example local_settings.py
sudo python manage.py syncdb
# follow prompts to setup django admin user

sudo chown -R www-data:www-data /opt/graphite/storage/
sudo service apache2 restart


####################################
# CREATE CARBON UPSTART SCRIPT
####################################
sudo adduser --no-create-home --disabled-password --gecos "" graphite
cat >> /tmp/carbon-cache.conf << EOF
#!/etc/init/carbon-cache.conf
description	"Carbon server"

start on filesystem or runlevel [2345]
stop on runlevel [!2345]

umask 022
expect daemon
respawn

pre-start script
    test -d /opt/graphite || { stop; exit 0; }
end script

chdir /opt/graphite

# Note the use of a wrapper so we can activate our virtualenv:
exec start-stop-daemon --oknodo --chdir /opt/graphite --user graphite --chuid graphite --pidfile /opt/graphite/storage/carbon-cache-a.pid --name carbon-cache --startas /opt/graphite/bin/run-carbon-cache.sh --start start
EOF
cat >> /tmp/run-carbon-cache.sh << EOF
#!/bin/sh
set -e
HOME=/opt/graphite
. /opt/graphite/.virtualenv/bin/activate
. /opt/graphite/.virtualenv/bin/postactivate
exec /opt/graphite/bin/carbon-cache.py "$@"
EOF
sudo cp /tmp/carbon-cache.conf /etc/init/carbon-cache.conf
sudo cp /tmp/run-carbon-cache.sh /opt/graphite/bin/run-carbon-cache.sh
sudo chmod +x /etc/init/carbon-cache.conf /opt/graphite/bin/run-carbon-cache.sh








####################################
# START CARBON
####################################
# cd /opt/graphite/
# sudo ./bin/carbon-cache.py start

####################################
# SEND DATA TO GRAPHITE
####################################
sudo python examples/example-client.py


####################################
# INSTALL STATSD
####################################
cd /opt && sudo git clone git://github.com/etsy/statsd.git
# StatsD configuration
cat >> /tmp/localConfig.js << EOF
{
  graphitePort: 2003
, graphiteHost: "127.0.0.1"
, port: 8125
}
EOF
sudo cp /tmp/localConfig.js /opt/statsd/localConfig.js

####################################
# CREATE STATSD UPSTART SCRIPT
####################################
# http://howtonode.org/deploying-node-upstart-monit
cat >> /tmp/statsd.conf << EOF
#!/etc/init/statsd.conf
description "statsd"

start on started mountall
stop on shutdown

respawn
respawn limit 99 5

script  
    export HOME="/root"
    exec sudo -u nobody node /opt/statsd/stats.js /etc/statsd/localConfig.js
end script

post-start script
   # Optionally put a script here that will notifiy you node has (re)started
   # /root/bin/hoptoad.sh "node.js has started!"
end script
EOF
sudo cp /tmp/statsd.conf /etc/init/statsd.conf
sudo chmod +x /etc/init/statsd.conf

####################################
# CREATE MONIT CONFIG
####################################
cat >> /tmp/statsd.monit.conf << EOF
check process statsd with pidfile "/var/run/statsd.pid"
     start program = "/sbin/start statsd"
     stop program  = "/sbin/stop statsd"
     if failed host localhost port 8125 type udp
         with timeout 10 seconds then restart
     if 5 restarts within 5 cycles then timeout
EOF
sudo cp /tmp/statsd.monit.conf /etc/monit/conf.d/statsd



