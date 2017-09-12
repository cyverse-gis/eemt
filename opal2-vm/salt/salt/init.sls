/etc/salt/minion.d:
  file.directory:
    - user: root
    - group: root
    - mode: 755
    - makedirs: True

/etc/salt/minion.d/sol-vm.conf:
  file.managed:
    - user: root
    - group: root
    - mode: 644
    - template: jinja
    - source: salt://salt/sol-vm.conf

/etc/cron.d/salt:
  file.managed:
    - source: salt://salt/cron.salt
    - user: root
    - group: root
    - mode: 644
    - template: jinja


