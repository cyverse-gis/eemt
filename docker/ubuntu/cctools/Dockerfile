FROM ubuntu:20.04

LABEL authors="Tyson L Swetnam"
LABEL maintainer="tswetnam@cyverse.org"

USER root

# system environment
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y software-properties-common build-essential wget curl \
    make gcc libgcc1 g++ ccache swig \
    libsocket++1 zlib1g-dev libglobus-gss-assist-dev libkrb5-dev libreadline-dev python-dev libmysqlclient-dev libfuse-dev libperl-dev ca-certificates m4

# Install CCTools
RUN cd /tmp && wget http://ccl.cse.nd.edu/software/files/cctools-stable-source.tar.gz && \
    tar xvzf cctools-stable-source.tar.gz

RUN cd /tmp/cctools-7.1.7-source && \
    ./configure --prefix /opt/cctools && \
    make clean && \
    make install

RUN rm -rf /tmp/cctools*

RUN apt-get autoremove \
    && apt-get clean 

RUN echo LANG="en_US.UTF-8" > /etc/default/locale
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# set SHELL var to avoid /bin/sh fallback in interactive
ENV SHELL /bin/bash

ENV PYTHON_PATH=/usr/bin/python3
ENV PERL5_LIB=/usr/bin/perl
ENV PATH=$PATH:$PYTHON_PATH

# Install CCTools
ENV PYTHONPATH=/opt/cctools/lib/python3.8/site-packages:${PYTHON_PATH}
ENV PERL5LIB=/opt/cctools/lib/perl5/site_perl/5.30.0:${PERL5LIB}
ENV PATH=$PATH:/opt/cctools/bin/

CMD ["work_queue_status"]
