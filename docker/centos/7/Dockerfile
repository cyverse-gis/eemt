FROM centos:7

LABEL authors="Tyson L Swetnam"
LABEL maintainer="tswetnam@cyverse.org"

USER root

# system environment
ENV DEBIAN_FRONTEND noninteractive

RUN yum update && \
    yum install -y wget curl \
    make gcc libgcc1 g++ ccache swig \
    libsocket++1 zlib1g-dev default-libmysqlclient-dev libfuse-dev libperl-dev ca-certificates

RUN cd /opt && wget https://ccl.cse.nd.edu/software/files/cctools-7.1.7-x86_64-centos7.tar.gz && \
    tar xvzf cctools-7.1.7-x86_64-centos7.tar.gz

RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# set SHELL var to avoid /bin/sh fallback in interactive
ENV SHELL /bin/bash
ENV PATH=$PATH:/opt/cctools-7.1.7-x86_64-centos7/bin/

CMD ["work_queue_status"]
