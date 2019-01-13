
epel-release:
  pkg:
    - installed

/etc/yum.repos.d/osg.repo:
  file:
    - managed
    - source: salt://yum/osg.repo
    - require:
      - pkg: epel-release
  
osg-oasis:
  pkg:
    - installed
    - require:
      - file: /etc/yum.repos.d/osg.repo

java-1.8.0-openjdk-devel:
  pkg:
    - installed

java-1.8.0-openjdk:
  pkg:
    - installed

ant:
  pkg:
    - installed

singularity:
  pkg:
    - installed

zip:
  pkg:
    - installed

