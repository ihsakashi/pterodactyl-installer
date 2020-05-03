#!/bin/bash

#############################################################################
#                                                                           #
# Project 'pterodactyl-installer' for wings                                 #
#                                                                           #
# Copyright (C) 2018 - 2020, Vilhelm Prytz, <vilhelm@prytznet.se>, et al.   #
#                                                                           #
# This script is licensed under the terms of the GNU GPL v3.0 license       #
# https://github.com/VilhelmPrytz/pterodactyl-installer/blob/master/LICENSE #
#                                                                           #
# This script is not associated with the official Pterodactyl Project.      #
# https://github.com/VilhelmPrytz/pterodactyl-installer                     #
#                                                                           #
#############################################################################

# exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  echo "* This script must be executed with root privileges (sudo)." 1>&2
  exit 1
fi

# check for curl
CURLPATH="$(command -v curl)"
if [ -z "$CURLPATH" ]; then
    echo "* curl is required in order for this script to work."
    echo "* install using apt (Debian and derivatives) or yum/dnf (CentOS)"
    exit 1
fi

# define version using information from GitHub
get_latest_release() {
  curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                            # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

echo "* Retrieving release information.."
VERSION="$(get_latest_release "pterodactyl/wings")"

echo "* Latest version is $VERSION"

# download URLs
DL_URL="https://github.com/pterodactyl/wings/releases/download/v1.0.0-beta.2/wings"
CONFIGS_URL="https://raw.githubusercontent.com/ihsakashi/pterodactyl-installer/pterodactyl-1.0/configs"

COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

INSTALL_MARIADB=false
INSTALL_CUSTOM=false

# visual functions
function print_error {
  echo ""
  echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
  echo ""
}

function print_warning {
  COLOR_YELLOW='\033[1;33m'
  COLOR_NC='\033[0m'
  echo ""
  echo -e "* ${COLOR_YELLOW}WARNING${COLOR_NC}: $1"
  echo ""
}

function print_brake {
  for ((n=0;n<$1;n++));
    do
      echo -n "#"
    done
    echo ""
}


# other functions
function detect_distro {
  if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$(echo "$ID" | awk '{print tolower($0)}')
    OS_VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si | awk '{print tolower($0)}')
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    OS="SuSE"
    OS_VER="?"
  elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS="Red Hat/CentOS"
    OS_VER="?"
  else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    OS_VER=$(uname -r)
  fi

  OS=$(echo "$OS" | awk '{print tolower($0)}')
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

function check_os_comp {
  if [ "$OS" == "ubuntu" ]; then
    if [ "$OS_VER_MAJOR" == "16" ]; then
      SUPPORTED=true
    elif [ "$OS_VER_MAJOR" == "18" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "zorin" ]; then
    if [ "$OS_VER_MAJOR" == "15" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "debian" ]; then
    if [ "$OS_VER_MAJOR" == "9" ]; then
      SUPPORTED=true
    elif [ "$OS_VER_MAJOR" == "10" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  elif [ "$OS" == "centos" ]; then
    if [ "$OS_VER_MAJOR" == "7" ]; then
      SUPPORTED=true
    elif [ "$OS_VER_MAJOR" == "8" ]; then
      SUPPORTED=true
    else
      SUPPORTED=false
    fi
  else
    SUPPORTED=false
  fi

  # exit if not supported
  if [ "$SUPPORTED" == true ]; then
    echo "* $OS $OS_VER is supported."
  else
    echo "* $OS $OS_VER is not supported"
    print_error "Unsupported OS"
    exit 1
  fi
}

############################
## INSTALLATION FUNCTIONS ##
############################
function apt_update {
  apt update -y
  apt upgrade -y
}

function install_dep {
  if [ "$OS" == "debian" ] || [ "$OS" == "ubuntu" ] || [ "$OS" == "zorin" ]; then
    apt_update

    # install dependencies
    apt -y install curl
  elif [ "$OS" == "centos" ]; then
    if [ "$OS_VER_MAJOR" == "7" ]; then
      yum -y update

      # install dependencies
      yum -y install curl
    elif [ "$OS_VER_MAJOR" == "8" ]; then
      dnf -y update

      # install dependencies
      dnf install -y curl
    fi
  else
    print_error "Invalid OS."
    exit 1
  fi
}
function install_docker {
  echo "* Installing docker .."
  if [ "$OS" == "debian" ]; then
    # install dependencies for Docker
    apt-get update
    apt-get -y install \
     apt-transport-https \
     ca-certificates \
     curl \
     gnupg2 \
     software-properties-common

    # get their GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -

    # show fingerprint to user
    apt-key fingerprint 0EBFCD88

    # add APT repo
    add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/debian \
      $(lsb_release -cs) \
      stable"

    # install docker
    apt-get update
    apt-get -y install docker-ce

    # make sure it's enabled & running
    systemctl start docker
    systemctl enable docker

  elif [ "$OS" == "ubuntu" ] || [ "$OS" == "zorin" ]; then
    # install dependencies for Docker
    apt-get update
    apt-get -y install \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common

    if [ "$OS_VER_MAJOR" >= "19" ]; then
      apt-get -y install docker.io
    else
      # get their GPG key
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

      # show fingerprint to user
      apt-key fingerprint 0EBFCD88

      # add APT repo
      sudo add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) \
      stable"

      # install docker
      apt-get update
      apt-get -y install docker-ce
    fi

    # make sure it's enabled & running
    systemctl start docker
    systemctl enable docker

  elif [ "$OS" == "centos" ]; then
    if [ "$OS_VER_MAJOR" == "7" ]; then
      # install dependencies for Docker
      yum install -y yum-utils device-mapper-persistent-data lvm2

      # add repo to yum
      yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo

      # install Docker
      yum install -y docker-ce
    elif [ "$OS_VER_MAJOR" == "8" ]; then
      # install dependencies for Docker
      dnf install -y dnf-utils device-mapper-persistent-data lvm2

      # add repo to dnf
      dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

      # install Docker
      dnf install -y docker-ce --nobest
    fi

    # make sure it's enabled & running
    systemctl start docker
    systemctl enable docker
  fi

  echo "* Docker has now been installed."
}

function ptdl_dl {
  echo "* Installing Pterodactyl Wings .. "

  mkdir -p /srv/wings/data/servers /srv/daemon-data
  cd /srv/wings || exit
  curl -L -o wings "$DL_URL"

  chmod u+x wings

  echo "* Done."
}

function systemd_file {
  echo "* Installing systemd service.."
  curl -o /etc/systemd/system/wings.service $CONFIGS_URL/wings.service
  systemctl daemon-reload
  systemctl enable wings
  echo "* Installed systemd service!"
}

function install_standalone_sftp_server {
  echo "* Installing standalone SFTP server.."

  INSTALL_PATH="/srv/wings/sftp-server"

  curl -Lo $INSTALL_PATH https://github.com/pterodactyl/sftp-server/releases/download/v1.0.4/sftp-server
  chmod +x $INSTALL_PATH

  curl -o /etc/systemd/system/pterosftp.service $CONFIGS_URL/pterosftp.service

  systemctl daemon-reload
  systemctl enable pterosftp
}

function install_mariadb {
  if [ "$OS" == "ubuntu" ] || [ "$OS" == "zorin" ] || [ "$OS" == "debian" ]; then
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
    apt update && apt install mariadb-server -y
  elif [ "$OS" == "centos" ]; then
    [ "$OS_VER_MAJOR" == "7" ] && curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
    [ "$OS_VER_MAJOR" == "7" ] && yum -y install mariadb-server
    [ "$OS_VER_MAJOR" == "8" ] && dnf install -y mariadb mariadb-server
  else
    print_error "Unsupported OS for MariaDB installations!"
  fi
  systemctl enable mariadb
  systemctl start mariadb
}

function install_custom {
  # FIREWALL
  rm -rf /etc/rc.local
  printf '%s\n' '#!/bin/bash' 'exit 0' | sudo tee -a /etc/rc.local
  chmod +x /etc/rc.local

  iptables -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP
  iptables -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
  iptables -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,FIN FIN -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL ALL -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP 
  iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP
  iptables -A INPUT -p tcp -m connlimit --connlimit-above 1000 --connlimit-mask 32 --connlimit-saddr -j REJECT --reject-with tcp-reset
  iptables -t mangle -A PREROUTING -f -j DROP
  /sbin/iptables -N port-scanning 
  /sbin/iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN 
  /sbin/iptables -A port-scanning -j DROP  
  sh -c "iptables-save > /etc/iptables.conf"
  sed -i -e '$i \iptables-restore < /etc/iptables.conf\n' /etc/rc.local

  apt -y install fail2ban
  systemctl enable fail2ban
  curl -o /etc/fail2ban/jail.local $CONFIGS_URL/jail.local
  service fail2ban restart

  # ubuntu specific
  apt-get -y install ufw
  ufw allow 22

  # daemon/wing specific
  ufw allow 80
  ufw allow 8080
  ufw allow 2022

  yes |ufw enable
  
}

####################
## MAIN FUNCTIONS ##
####################
function perform_install {
  echo "* Installing pterodactyl wings.."

  install_dep
  install_docker
  ptdl_dl
  systemd_file
  [ "$INSTALL_MARIADB" == true ] && install_mariadb
  [ "$INSTALL_CUSTOM" == true ] && install_custom

  # return true if script has made it this far
  return 0
}

function main {
  # check if we can detect an already existing installation
  if [ -d "/srv/wings" ]; then
    print_warning "The script has detected that you already have Pterodactyl wings on your system! You cannot run the script multiple times, it will fail!"
    echo -e -n "* Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      print_error "Installation aborted!"
      exit 1
    fi
  fi

  # detect distro
  detect_distro

  print_brake 70
  echo "* Pterodactyl Wings installation script"
  echo "*"
  echo "* Copyright (C) 2018 - 2020, Vilhelm Prytz, <vilhelm@prytznet.se>, et al."
  echo "* https://github.com/VilhelmPrytz/pterodactyl-installer"
  echo "*"
  echo "* This script is not associated with the official Pterodactyl Project."
  echo "*"
  echo "* Running $OS version $OS_VER."
  print_brake 70

  # checks if the system is compatible with this installation script
  #check_os_comp
  # UBUNTU 20.04

  echo "* "
  echo "* The installer will install Docker, required dependencies for Wings"
  echo "* as well as Wings itself. But it's still required to create the node"
  echo "* on the panel and then place the configuration file on the node manually after"
  echo "* the installation has finished. Read more about this process on the"
  echo "* official documentation: https://pterodactyl.io/daemon/installing.html#configure-daemon"
  echo "* "
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: this script will not start Wings automatically (will install systemd service, not start it)."
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: this script will not enable swap (for docker)."
  print_brake 42

  echo -e "* ${COLOR_RED}Note${COLOR_NC}: If you installed the Pterodactyl panel on the same machine, do not use this option or the script will fail!"

  echo -e "* ${COLOR_RED}Note${COLOR_NC}: You have to certbot SSL yourself."

  echo -n "* Would you like to install MariaDB (MySQL) server on the daemon as well? (y/N): "

  read -r CONFIRM_INSTALL_MARIADB
  [[ "$CONFIRM_INSTALL_MARIADB" =~ [Yy] ]] && INSTALL_MARIADB=true

  echo -e "* PERFORM CUSTOM FUNCTION? (y/N): "

  read -r CONFIRM_INSTALL_CUSTOM
  [[ "$CONFIRM_INSTALL_CUSTOM" =~ [Yy] ]] && INSTALL_CUSTOM=true


  echo -n "* Proceed with installation? (y/N): "

  read -r CONFIRM
  [[ "$CONFIRM" =~ [Yy] ]] && perform_install && return

  print_error "Installation aborted"
  exit 0
}

function goodbye {
  echo ""
  print_brake 70
  echo "* Installation completed."
  echo ""
  echo "* Make sure you create the node within the panel and then copy"
  echo "* the config to this node. You may then start the daemon using "
  echo "* systemctl start wings"
  echo "* "
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: It is recommended to enable swap (for Docker, read more about it in official documentation)."
  #echo -e "* ${COLOR_RED}Note${COLOR_NC}: This script does not configure your firewall. Ports 8080 and 2022 needs to be open."
  echo -e "* ${COLOR_RED}Note${COLOR_NC}:
  print_brake 70
  echo ""
}

# run script
main
goodbye
