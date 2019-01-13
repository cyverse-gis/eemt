
/srv/opal2-services:
  file.directory:
    - user: eemt
    - group: eemt
    - mode: 755

/srv/opal2-services/solot.xml:
  file.managed:
    - user: eemt
    - group: eemt
    - mode: 644
    - source: salt://opal2/solot.xml

/usr/sbin/redeploy-opal2:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - template: jinja
    - source: salt://opal2/redeploy-opal2

/usr/sbin/redeploy-opal2 2>&1 | tee /var/log/redeploy-opal2.log:
  cmd.run:
    - creates:
      - /srv/tomcat

/srv/tomcat/conf/web.xml:
  file.managed:
    - source: salt://opal2/web.xml

/etc/init.d/tomcat:
  file.managed:
    - user: root
    - group: root
    - mode: 755
    - source: salt://opal2/tomcat-init.sh

tomcat:
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /srv/tomcat/conf/web.xml

/vol_c/eemtws-jobs:
  file.directory:
    - user: eemt
    - group: eemt
    - mode: 755

/srv/tomcat/webapps/eemtws-jobs:
  file.symlink:
    - target: /vol_c/eemtws-jobs

