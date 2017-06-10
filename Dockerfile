############  OS  #############
FROM centos:7 

############ BASE #############
ENV APP_HOME=/opt/app
ENV CATALINA_HOME=$APP_HOME/tomcat \
    JAVA_HOME=$APP_HOME/jre
ENV TOMCAT_NATIVE_LIBDIR=$CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR \
    PATH=$CATALINA_HOME/bin:$PATH \
    TOMCAT_MAJOR=8 \
    TOMCAT_VERSION=8.5.15
WORKDIR $CATALINA_HOME

# Local files. copy files to workdir
COPY jdk-8u121-linux-x64.tar.gz . 
COPY apache-tomcat-8.5.15.tar.gz .   
COPY apache-tomcat-8.5.15.tar.gz.asc . 
COPY openssl-1.0.2l.tar.gz .

# JDK
RUN set -x \
      && ( \
         cd "$APP_HOME" \
         && tar -xvf "$CATALINA_HOME"/jdk-8u121-linux-x64.tar.gz jdk1.8.0_121/jre --strip-components=1 \
         && cd "$JAVA_HOME" \
         && tar -xvf "$CATALINA_HOME"/jdk-8u121-linux-x64.tar.gz jdk1.8.0_121/include --strip-components=1 \
         ) \
      && rm -rf jdk-8u121-linux-x64.tar.gz

# YUM
RUN yum install -y wget \
    && mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup \
    && wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo \
    && yum clean all 


########### RUN #############
# PGP&GPG See: https://www.apache.org/dist/tomcat/tomcat-8/KEY
RUN curl -fsSL "https://www.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR/KEYS" | gpg --import

# Tomcat
RUN set -x \
      && gpg --batch --verify  apache-tomcat-8.5.15.tar.gz.asc apache-tomcat-8.5.15.tar.gz \
      && tar -xvf apache-tomcat-8.5.15.tar.gz --strip-components=1 \
      && rm -f bin/*.bat \
      && rm -f apache-tomcat*

# depend
RUN set -x \
      && yum install -y gcc apr-devel perl make which\
      && yum clean all

# openssl 
ENV PATH=/usr/local/ssl/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/ssl/lib:$LD_LIBRARY_PATH
RUN set -x \
      && opensslBuildDir="$(mktemp -d)" \
      && tar -xvf openssl-1.0.2l.tar.gz -C "$opensslBuildDir" --strip-components=1 \
      && rm -f openssl-1.0.2l.tar.gz \
      && ( \
        cd "$opensslBuildDir" \
        && ./config -fPIC shared \
        && make \
        && make install \
        ) \
     && rm -rf "$opensslBuildDir"

# tomcat native
RUN set -x \
      && nativeBuildDir="$(mktemp -d)" \
      && tar -xvf bin/tomcat-native.tar.gz -C "$nativeBuildDir" --strip-components=1 \
      && ( \ 
        cd "$nativeBuildDir/native" \
        && gnuArch="$(arch)" \
        && ./configure \
             --build="$gnuArch" \
             --prefix="$CATALINA_HOME" \
             --with-apr=$(which apr-1-config) \
             --libdir="$TOMCAT_NATIVE_LIBDIR" \
             --with-ssl=yes \
             --with-java-home="$JAVA_HOME" \
        && make \
        && make install \
        ) \
     && rm -rf "$nativeBuildDir" \
     && rm -f bin/tomcat-native.tar.gz 

########### VERIFY ##########
RUN set -e \
      && nativeLines="$(catalina.sh configtest 2>&1)" \
      && nativeLines="$(echo "$nativeLines" | grep 'Apache Tomcat Native')" \
      && nativeLines="$(echo "$nativeLines" | sort -u)" \
      && if ! echo "$nativeLines" | grep 'INFO: Loaded APR based Apache Tomcat Native library' >&2; then \
		echo >&2 "$nativeLines"; \
		exit 1; \
	fi

EXPOSE 8080 
CMD ["catalina.sh", "run"]
