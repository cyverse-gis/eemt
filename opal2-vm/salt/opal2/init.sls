
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

