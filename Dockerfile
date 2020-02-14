FROM php:7.1-apache

#Install libs
RUN apt-get update && apt-get install -y \
        libpq-dev \
        wget \
        unzip \
        alien \
        libaio1 \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libxml2-dev \
        libldap2-dev \
        libldb-dev \
    && mkdir -p /opt/ibm/db2/

#Install drivers DB's
COPY files/ibm_data_server_driver_package_linuxx64_v11.1.tar.gz /opt/ibm/db2/drive-ibm.tar.gz
COPY files/oracle-instantclient12.2-basic-12.2.0.1.0-1.x86_64.rpm /tmp/oracle-oci12.rpm
COPY files/oracle-instantclient12.2-devel-12.2.0.1.0-1.x86_64.rpm /tmp/oracle-oci12-devel.rpm
ADD  files/PDO_IBM-1.3.4-patched.tar.xz /tmp/

#Include Oracle Environment Variable
ENV ORACLE_HOME=/usr/lib/oracle/12.2/client64 \
    IBM_DB_HOME=/opt/ibm/db2/dsdriver \
    PATH=$PATH:/usr/lib/oracle/12.2/client64/bin \
    LD_LIBRARY_PATH=/usr/lib/oracle/12.2/client64/lib:/opt/ibm/db2/dsdriver/lib

#Include DB2 Environment Variable
RUN cd /opt/ibm/db2/ \
    && ln -s $IBM_DB_HOME/include /include \
    && tar -xzf drive-ibm.tar.gz \
    && /bin/bash $IBM_DB_HOME/installDSDriver \
    && cd /tmp  \
    && alien -i oracle-oci12.rpm oracle-oci12-devel.rpm \
    && pecl install xdebug-2.6.0 \
    && printf $IBM_DB_HOME | pecl install ibm_db2 \

#Configure PDO DB2
    && cd /tmp/PDO_IBM-1.3.4-patched \
    && phpize \
    && ./configure --with-pdo-ibm=$IBM_DB_HOME/lib \
    && make -j "$(nproc)" \
    && make install \

#Configure Oci8 and PGSql
    && docker-php-ext-configure oci8 --with-oci8=instantclient,/usr/lib/oracle/12.2/client64/lib \
    && docker-php-ext-configure pdo_oci --with-pdo-oci=instantclient,/usr,12.2 \
    && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \

#Configure LDAP
    && docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu \
    && docker-php-ext-install -j$(nproc) oci8 pgsql pdo pdo_oci pdo_pgsql soap mysqli pdo_mysql ldap \
    && docker-php-ext-enable  ibm_db2 pdo_ibm xdebug soap \
    && docker-php-ext-install gd

#Rename php.ini
RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

#Install ODBD and PDO_ODBC
RUN set -e; \
  BUILD_PACKAGES="libzip-dev libssh2-1-dev unixodbc-dev"; \
  apt-get update; \
  apt-get install -y $BUILD_PACKAGES; \
  set +e; \
  docker-php-ext-install odbc; \
  set -e; \
  cd /usr/src/php/ext/odbc; \
  phpize; \
  sed -ri 's@^ *test +"\$PHP_.*" *= *"no" *&& *PHP_.*=yes *$@#&@g' configure; \
  ./configure --with-unixODBC=shared,/usr; \
  cd /root; \
  yes | pecl install ssh2-1.1.2; \
  docker-php-ext-configure pdo_odbc --with-pdo-odbc=unixODBC,/usr; \
  docker-php-ext-install pdo_odbc odbc; \
  docker-php-ext-enable ssh2; \
  apt-get remove --purge -y $BUILD_PACKAGES && rm -rf /var/lib/apt/lists/*; \
  apt-get clean;

RUN a2enmod rewrite \
   && service apache2 restart



