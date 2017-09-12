
/etc/auto.master:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - source: salt://cvmfs/auto.master

/etc/cvmfs/default.local: 
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - source: salt://cvmfs/default.local

autofs:
  pkg:
    - installed
    - name: autofs
  service.running:
    - enable: True
    - reload: True
    - watch:
      - file: /etc/auto.master
      - file: /etc/cvmfs/default.local


