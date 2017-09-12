
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

