
tswetnam:
  group.present: []
  user.present:
    - shell: /bin/bash
    - home: /home/tswetnam
    - remove_groups: False
    - groups:
      - tswetnam
      - users

rynge:
  group.present: []
  user.present:
    - shell: /bin/bash
    - home: /home/rynge
    - remove_groups: False
    - groups:
      - rynge
      - users

yanliu:
  group.present: []
  user.present:
    - shell: /bin/bash
    - home: /home/yanliu
    - remove_groups: False
    - groups:
      - yanliu
      - users

eemt:
  group.present:
    - gid: 1000
  user.present:
    - uid: 1000
    - shell: /bin/bash
    - home: /home/eemt
    - remove_groups: False
    - groups:
      - eemt
      - users

/home/tswetnam/.ssh:
  file.directory:
    - user: tswetnam
    - group: tswetnam
    - mode: 755
    - makedirs: True
    - require:
      - user: tswetnam

/home/tswetnam/.ssh/authorized_keys:
  file.managed:
    - user: tswetnam
    - group: tswetnam
    - mode: 644
    - template: jinja
    - source: salt://users/authorized_keys.tswetnam

/home/rynge/.ssh:
  file.directory:
    - user: rynge
    - group: rynge
    - mode: 755
    - makedirs: True
    - require:
      - user: rynge

/home/rynge/.ssh/authorized_keys:
  file.managed:
    - user: rynge
    - group: rynge
    - mode: 644
    - template: jinja
    - source: salt://users/authorized_keys.rynge

/home/yanliu/.ssh:
  file.directory:
    - user: yanliu
    - group: yanliu
    - mode: 755
    - makedirs: True
    - require:
      - user: yanliu

/home/yanliu/.ssh/authorized_keys:
  file.managed:
    - user: yanliu
    - group: yanliu
    - mode: 644
    - template: jinja
    - source: salt://users/authorized_keys.yanliu

/home/eemt/.bashrc:
  file.append:
    - text:
      - "export JAVA_OPTS=\"-Djava.security.egd=file:/dev/urandom\""
      - "export CATALINA_HOME=/srv/tomcat"
      - "export OPAL_HOME=/srv/opal-ws"

/home/eemt/.ssh:
  file.directory:
    - user: eemt
    - group: eemt
    - mode: 755
    - makedirs: True
    - require:
      - user: eemt

/home/eemt/.ssh/authorized_keys:
  file.managed:
    - user: eemt
    - group: eemt
    - mode: 644
    - template: jinja
    - source: salt://users/authorized_keys.all

/root/.ssh:
  file.directory:
    - user: root
    - group: root
    - mode: 700
    - makedirs: True

#/root/.ssh/authorized_keys:
#  file.managed:
#    - user: root
#    - group: root
#    - mode: 644
#    - template: jinja
#    - source: salt://users/authorized_keys.all


