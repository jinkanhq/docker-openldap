![](https://img.shields.io/github/workflow/status/jinkanhq/docker-openldap/Build)
![](https://img.shields.io/docker/pulls/jinkanhq/openldap)
![](https://img.shields.io/docker/v/jinkanhq/openldap)
![](https://img.shields.io/badge/license-OpenLDAP%20License-green)

# OpenLDAP Docker Image

Out of box OpenLDAP docker image based on Debian Stable.

## Example

TLS enabled with global `ssf=128`.

```yaml
version: '3'

services:
  openldap:
    hostname: openldap
    image: jinkanhq/openldap
    environment:
      - LDAP_TLS_ENABLED=true
      - LDAP_TLS_CA_FILE=/certs/ca.crt
      - LDAP_TLS_CRT_FILE=/certs/server.crt
      - LDAP_TLS_KEY_FILE=/certs/server.pem
      - LDAP_TLS_DHPARAM_FILE=/certs/dhparam
      - LDAP_DOMAIN=jinkan.org
    ports:
      - "636:636"
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro
      - ./certs:/certs:ro
      - ./config:/usr/local/etc/slapd.d
      - ./data:/usr/local/var/openldap-data
```

Without TLS enabled.

```yaml
version: '3'

services:
  openldap:
    hostname: openldap
    image: jinkanhq/openldap
    environment:
      - LDAP_TLS_ENABLED=true
      - LDAP_TLS_CA_FILE=/certs/ca.crt
      - LDAP_TLS_CRT_FILE=/certs/server.crt
      - LDAP_TLS_KEY_FILE=/certs/server.pem
      - LDAP_TLS_DHPARAM_FILE=/certs/dhparam
      - LDAP_DOMAIN=jinkan.org
    ports:
      - "389:389"
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config:/usr/local/etc/slapd.d
      - ./data:/usr/local/var/openldap-data
```

# Environment Variables

## Basic

| Variable | Description | Default |
| :------- | :---------- | :------ |
| DEBUG | Entrypoint debug mode | `false` |
| LDAP_ORGANIZATION | Organization name| `Example` |
| LDAP_DOMAIN | Organization domain | `example.com` |
| LDAP_ROOT_CN | Root common name | `admin` |
| LDAP_ROOT_PASSWORD | Root password | `admin` |
| LDAP_DEBUG_LEVEL | [Debug level](https://www.openldap.org/doc/admin26/runningslapd.html) | `stats` |

## TLS

| Variable | Description | Default |
| :------- | :---------- | :------ |
| LDAP_TLS_ENABLED | Entrypoint debug mode | `false` |
| LDAP_TLS_CA_FILE | CA certificate file| `/etc/ssl/certs/ca-certificates.crt` |
| LDAP_TLS_CRT_FILE | Server certificate file |  |
| LDAP_TLS_KEY_FILE | Server private key file |  |
| LDAP_TLS_DHPARAM_FILE | DH parameter file | See ["Defaults"](#tls-defaults) |
| LDAP_TLS_CIPHER_SUITE | OpenSSL cipher suite | See ["Defaults"](#tls-defaults) |
| LDAP_TLS_SSF | [Security strength factor](https://www.openldap.org/doc/admin26/security.html#Security%20Strength%20Factors) | `ssf=128` |
| LDAP_TLS_VERIFY_CLIENT | What checks to perform on client certificates | `never` |

### TLS Defaults

These defaults follow [Mozilla](https://ssl-config.mozilla.org/)'s
recommendations. The *Intermediate* configuration is chosen as defaults for
general purpose.


#### DH Parameter

`https://ssl-config.mozilla.org/ffdhe2048.txt` is saved in
`/usr/local/etc/openldap/dhparam` as the default DH parameter.

#### Cipher Suite

The following is the recommended cipher suite in OpenSSL format.

```
ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA38
```

---

![Included OpenLDAP](https://www.openldap.org/images/powered/openldap-inc.gif)

<img src="https://jinkan.org/img/jinkan_logo_hori_grad.png" alt="Jinkan" width="180px">
