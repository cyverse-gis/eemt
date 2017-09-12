
/etc/sysconfig/iptables:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - source: salt://fw/iptables

iptables:
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/sysconfig/iptables


