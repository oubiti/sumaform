include:
  - suse_manager_proxy.repos
  - suse_manager_proxy.development

proxy-packages:
  pkg.latest:
    {% if 'head' in grains['version'] %}
    - fromrepo: Devel_Galaxy_Manager_Head
    - name: patterns-suma_proxy
    {% elif '3.0-released' in grains['version'] %}
    - fromrepo: SUSE-Manager-Proxy-3.0-x86_64-Pool
    - name: patterns-suma_proxy
    {% elif '3.0-nightly' in grains['version'] %}
    - fromrepo: Devel_Galaxy_Manager_3.0
    - name: patterns-suma_proxy
    {% elif '3.1-released' in grains['version'] %}
    - fromrepo: SUSE-Manager-Proxy-3.1-x86_64-Pool
    - name: patterns-suma_proxy
    {% elif '3.1-nightly' in grains['version'] %}
    - fromrepo: Devel_Galaxy_Manager_3.1
    - name: patterns-suma_proxy
    {% endif %}
    - require:
      - sls: suse_manager_proxy.repos

wget:
  pkg.installed:
    - require:
      - sls: suse_manager_proxy.repos

{% if grains['use_avahi'] %}

squid-configuration-dns-multicast:
  file.replace:
    - name: /usr/share/doc/proxy/conf-template/squid.conf
    - pattern: ^dns_multicast_local .*$
    - repl: dns_multicast_local on
    - append_if_not_found: True
    - require:
      - proxy-packages

squid-configuration-unknown-nameservers:
  file.replace:
    - name: /usr/share/doc/proxy/conf-template/squid.conf
    - pattern: ^ignore_unknown_nameservers .*$
    - repl: ignore_unknown_nameservers off
    - append_if_not_found: True
    - require:
      - proxy-packages

{% endif %}


{% if grains.get('auto_register') | default(true, true) %}

base_bootstrap_script:
  file.managed:
    - name: /root/bootstrap.sh
    - source: http://{{grains['server']}}/pub/bootstrap/bootstrap.sh
    - source_hash: http://{{grains['server']}}/pub/bootstrap/bootstrap.sh.sha512
    - mode: 755

bootstrap_script:
  file.replace:
    - name: /root/bootstrap.sh
    - pattern: ^PROFILENAME="".*$
    {% if grains['hostname'] and grains['domain'] %}
    - repl: PROFILENAME="{{ grains['hostname'] }}.{{ grains['domain'] }}"
    {% else %}
    - repl: PROFILENAME="{{grains['fqdn']}}"
    {% endif %}
    - require:
      - file: base_bootstrap_script
  cmd.run:
    - name: /root/bootstrap.sh
    - require:
      - file: bootstrap_script
      - pkg: proxy-packages
      - pkg: wget

{% endif %}


{% if grains.get('download_private_ssl_key') | default(true, true) %}

internal-trusted-cert:
  file.managed:
    - name: /usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT
    - source: http://{{grains['server']}}/pub/RHN-ORG-TRUSTED-SSL-CERT
    - source_hash: http://{{grains['server']}}/pub/RHN-ORG-TRUSTED-SSL-CERT.sha512
    - requires:
      - pkg: proxy-packages

ssl-build-directory:
  file.directory:
    - name: /root/ssl-build

ssl-building-trusted-cert:
  file.managed:
    - name: /root/ssl-build/RHN-ORG-TRUSTED-SSL-CERT
    - source: /usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT
    - requires:
      - file: internal-trusted-cert
      - file: ssl-build-directory

ssl-building-private-ssl-key:
  file.managed:
    - name: /root/ssl-build/RHN-ORG-PRIVATE-SSL-KEY
    - source: http://{{grains['server']}}/pub/RHN-ORG-PRIVATE-SSL-KEY
    - source_hash: http://{{grains['server']}}/pub/RHN-ORG-PRIVATE-SSL-KEY.sha512
    - requires:
      - pkg: proxy-packages
      - file: ssl-build-directory

ssl-building-ca-configuration:
  file.managed:
    - name: /root/ssl-build/rhn-ca-openssl.cnf
    - source: http://{{grains['server']}}/pub/rhn-ca-openssl.cnf
    - source_hash: http://{{grains['server']}}/pub/rhn-ca-openssl.cnf.sha512
    - requires:
      - pkg: proxy-packages
      - file: ssl-build-directory

{% endif %}

{% if grains.get('auto_configure') | default(true, true) %}

/root/config-answers.txt:
  file.managed:
    - source: salt://suse_manager_proxy/config-answers.txt
    - template: jinja

configure-proxy:
  cmd.run:
    - name: configure-proxy.sh --non-interactive --rhn-user={{ grains.get('server_username') | default('admin', true) }} --rhn-password={{ grains.get('server_password') | default('admin', true) }} --answer-file=/root/config-answers.txt ; true
    - env:
      - SSL_PASSWORD: spacewalk
    - creates: /srv/www/htdocs/pub/RHN-ORG-TRUSTED-SSL-CERT
    - requires:
      - pkg: proxy-packages
      - file: /root/config-answers.txt
      - file: ssl-building-trusted-cert
      - file: ssl-building-private-ssl-key
      - file: ssl-building-ca-configuration

{% endif %}
