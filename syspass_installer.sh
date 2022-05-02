#!/bin/bash
#########################################################################################################
##Syspass installation script 											                               ##
##Date: 02/12/2021                                                                                     ##
##Version 1.0:  Allows simple installation of Syspass.							                       ##
##        If the installation of all components is done on the same machine                            ##
##        a fully operational version remains. If installed on different machines                      ##
##        it is necessary to modify the configuration manually.                                        ##
##        Fully automatic installation only requires a password change at the end if you want.         ##
##                                                                                                     ##
##Authors:                                                                                             ##
##			Manuel José Beiras Belloso																   ##
#########################################################################################################
# Initial check that validates if you are root and if the operating system is Ubuntu
function initialCheck() {
	if ! isRoot; then
		echo "The script has to be executed as root"
		exit 1
	fi
}

# Function that checks to run the script as root
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
	checkOS
}

# Function that checks the operating system
function checkOS() {
	source /etc/os-release
	if [[ $ID == "ubuntu" ]]; then
		OS="ubuntu"
		MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
		if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
			echo "⚠️ This script is not tested on your version of Ubuntu. Do you want to continue?"
			echo ""
			CONTINUE='false'
			until [[ $CONTINUE =~ (y|n) ]]; do
				read -rp "Continue? [y/n]: " -e CONTINUE
			done
			if [[ $CONTINUE == "n" ]]; then
				exit 1
			fi
		fi
		QuestionsMenu
	else
		echo "Your operating system is not Ubuntu, in case it is Centos you can continue from here. Press [Y]"
		CONTINUE='false'
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
		OS="centos"
		QuestionsMenu
	fi
}

function QuestionsMenu() {
    echo "What do you want to do ?"
    echo "1. Syspass."
    echo "2. Delete everything."
    echo "3. exit."
    read -e CONTINUE
    if [[ CONTINUE -eq 1 ]]; then
        installSyspass
    elif [[ CONTINUE -eq 2 ]]; then
        uninstallAll
    elif [[ CONTINUE -eq 3 ]]; then
        exit 1
    else
        echo "invalid option !"
        QuestionsMenu
    fi
}

function installSyspass() {
    if [[ $OS == "ubuntu" ]]; then
        if dpkg -l | grep mariadb > /dev/null; then
            echo "Mariadb is already installed on your system."
            echo "The installation does not continue."
        else
            apt-get -y update && apt-get -y upgrade && apt-get -y install software-properties-common
             ## Add PGP key of mariadb.
            apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
            add-apt-repository 'deb [arch=amd64] http://mariadb.mirror.globo.tech/repo/10.5/ubuntu focal main'
            apt -y update && apt -y upgrade
            # Install mariadb.
            apt -y install mariadb-server mariadb-client
            # Restart service to fix error: ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/run/mysqld/mysqld.sock' (2)
            service mariadb restart
            echo ""
            echo ""
            echo "We automate mysql_secure_installation, user: root, password: abc123., never show username or password production. Just test pourpose."
            echo ""
            echo ""
            # Change the root password?
            mysql -e "SET PASSWORD FOR root@localhost = PASSWORD('abc123.');FLUSH PRIVILEGES;"
            # Remove anonymous users
            mysql -e "DELETE FROM mysql.user WHERE User='';"
            # Disallow root login remotely?
            mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
            # Remove test database and access to it?
            mysql -e "DROP DATABASE test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';"
            # Reload privilege tables now?
            mysql -e "flush privileges;"
        fi
        if dpkg -l | grep apache2 > /dev/null; then
            echo "Apache2 is already installed on your system."
            echo "The installation does not continue."
        else
            apt-get -y install apache2
            systemctl enable --now apache2
            ufw allow Apache 
        fi
        if dpkg -l | grep php > /dev/null; then
            echo "PHP is already installed on your system."
            echo "The installation does not continue."
        else
            add-apt-repository ppa:ondrej/php
            apt-get -y install libapache2-mod-php7.4 php-pear php7.4 php7.4-cgi php7.4-cli php7.4-common php7.4-fpm php7.4-gd php7.4-json php7.4-mysql php7.4-readline php7.4 curl php7.4-intl php7.4-ldap php7.4-mcrypt php7.4-xml php7.4-mbstring
        fi
        if dpkg -l | grep syspass > /dev/null; then
            echo "Syspass is already installed on your system."
            echo "The installation does not continue."
        else
            apt install -y locales 
            service apache2 restart
            mkdir /var/www/html/syspass
            cd /var/www/html/syspass
            git clone https://github.com/nuxsmin/sysPass.git  /var/www/html/syspass
            chown www-data -R /var/www/html/syspass
            chmod 750 /var/www/html/syspass/app/config /var/www/html/syspass/app/backup
            cat << EOF > install_composer.sh
#!/bin/sh
EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]
then
    >&2 echo 'ERROR: Invalid installer signature'
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --quiet
RESULT=$?
rm composer-setup.php
exit $RESULT
EOF
            chmod +x install_composer.sh
            ./install_composer.sh
            php composer.phar install --no-dev
        fi
    elif [[ $OS == "centos" ]]; then
        if rpm -qa | grep mariadb > /dev/null; then
            echo "Mysql is already installed on your system."
            echo "The installation does not continue."
        else
            yum -y install centos-release-scl.noarch
            yum -y install mariadb-server mariadb
            # Reiniciamos servicio para arreglar error: ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/run/mysqld/mysqld.sock' (2)
            systemctl restart mariadb
            echo ""
            echo ""
            echo "Automatizamos mysql_secure_installation, usuario: root, password: abc123., nunca mostar usuario ni contraseña producción. Solo prueba."
            echo ""
            echo ""
            # Change the root password?
            mysql -e "UPDATE mysql.user SET Password = PASSWORD('abc123.') WHERE User = 'root'"
            # Remove anonymous users
            mysql -e "DELETE FROM mysql.user WHERE User='';"
            # Disallow root login remotely?
            mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
            # Remove test database and access to it?
            mysql -e "DROP DATABASE test;DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';"
            # Reload privilege tables now?
            mysql -e "flush privileges;"
        fi
        if rpm -qa | grep apache2 > /dev/null; then
            echo "Apache2 is already installed on your system."
            echo "The installation does not continue."
        else
            yum -y install httpd
            systemctl enable --now httpd24-httpd.service mariadb.service
        fi
        if rpm -qa | grep php > /dev/null; then
            echo "PHP is already installed on your system."
            echo "The installation does not continue."
        else
            yum -y install yum-utils wget
            yum -y install epel-release
            yum -y install http://rpms.remirepo.net/enterprise/remi-release-7.rpm
            yum-config-manager ––enable remi–php74
            yum -y install libapache2-mod-php7.4 php-pear php7.4 php7.4-cgi php7.4-cli php7.4-common php7.4-fpm php7.4-gd php7.4-json php7.4-mysql php7.4-readline php7.4 curl php7.4-intl php7.4-ldap php7.4-mcrypt php7.4-xml php7.4-mbstring
            firewall-cmd --zone=public --add-service=http --add-service=https
            firewall-cmd --runtime-to-permanent
        fi
        if rpm -qa | grep syspass > /dev/null; then
            echo "Syspass is already installed on your system."
            echo "The installation does not continue."
        else
            yum -y install git
            service httpd restart
            mkdir /var/www/html/syspass
            cd /var/www/html/syspass
            git clone https://github.com/nuxsmin/sysPass.git  /var/www/html/syspass
            chown apache -R /var/www/html/syspass
            #chown www-data -R /var/www/html/syspass
            chmod 750 /var/www/html/syspass/app/config /var/www/html/syspass/app/backup
            cat << EOF > install_composer.sh
#!/bin/sh
EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]
then
    >&2 echo 'ERROR: Invalid installer signature'
    rm composer-setup.php
    exit 1
fi

php composer-setup.php --quiet
RESULT=$?
rm composer-setup.php
exit $RESULT
EOF
            chmod +x install_composer.sh
            ./install_composer.sh
            php composer.phar install --no-dev
        fi
    fi
    QuestionsMenu
}

function uninstallAll() {
    if [[ $OS == "ubuntu" ]]; then
        apt-get -y remove mariadb-server mariadb-client software-properties-common libdbd-mariadb-perl
        apt-get -y  purge mariadb-server mariadb-client software-properties-common libdbd-mariadb-perl
        apt-get -y  purge mariadb-server-*
        apt-get -y  purge mariadb-server-10.3
        apt-get -y  purge mariadb-server-10.5
        apt-get -y  purge mariadb-client-*
        apt-get -y  purge mariadb-common
        apt remove -y php*
        apt remove -y php7.4-*
        apt remove -y php-*
        apt remove -y libapache2-mod-php*
        apt purge y php*
        apt purge -y php7.4-*
        apt purge -y php-*
        apt purge -y libapache2-mod-php*
        apt remove -y apache2*
        apt remove -y libapache2-mod-* 
        apt purge -y apache2*
        apt purge -y libapache2-mod-* 
        rm -r /var/www/html/syspass
        echo "All uninstalled."
        exit 1
    elif [[ $OS == "centos" ]]; then
        yum -y remove centos-release-scl.noarch
        yum -y remove mariadb-server mariadb
        yum -y remove mariadb-*
        yum -y remove httpd
        yum -y remove httpd*
        yum -y libapache2-mod-php7.4 php-pear php7.4 php7.4-cgi php7.4-cli php7.4-common php7.4-fpm php7.4-gd php7.4-json php7.4-mysql php7.4-readline php7.4 curl php7.4-intl php7.4-ldap php7.4-mcrypt php7.4-xml php7.4-mbstring
        yum -y remove rh-php73 rh-php73-php rh-php73-php-fpm wget
        yum -y remove rh-php73-runtime-1-1.el7.x86_64
        yum -y remove rh-php73-php-gd rh-php73-php-intl rh-php73-php-json rh-php73-php-ldap rh-php73-php-mbstring rh-php73-php-mysqlnd rh-php73-php-opcache rh-php73-php-pdo rh-php73-php-xml rh-php73-php-zip
        yum -y erase centos-release-scl.noarch
        yum -y erase mariadb-server
        yum -y erase mariadb-*
        yum -y erase httpd
        yum -y erase httpd*
        yum -y erase libapache2-mod-php7.4 php-pear php7.4 php7.4-cgi php7.4-cli php7.4-common php7.4-fpm php7.4-gd php7.4-json php7.4-mysql php7.4-readline php7.4 curl php7.4-intl php7.4-ldap php7.4-mcrypt php7.4-xml php7.4-mbstring
        yum -y erase rh-php73 rh-php73-php rh-php73-php-fpm wget
        yum -y erase rh-php73-runtime-1-1.el7.x86_64
        yum -y erase rh-php73-php-gd rh-php73-php-intl rh-php73-php-json rh-php73-php-ldap rh-php73-php-mbstring rh-php73-php-mysqlnd rh-php73-php-opcache rh-php73-php-pdo rh-php73-php-xml rh-php73-php-zip
        rm -r /var/www/html/syspass
        echo "All uninstalled."
        exit 1
    fi
}

initialCheck
