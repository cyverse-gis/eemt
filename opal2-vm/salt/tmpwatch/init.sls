
/etc/cron.d/tmpwatch:
  file.managed:
    - source: salt://tmpwatch/tmpwatch.cron
    - user: root
    - group: root
    - mode: 644


