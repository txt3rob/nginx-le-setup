#!/bin/bash
#
# Setup a virtual host with a let's encrypt certificate
#
# This script assumes that your nginx default servername
# is configured for lets encrypt
#

if [ "$(id -u)" != "0" ]; then
    echo "This script requires root privileges."
    exit 1
fi

CONFIRM=0
NGINX_DIR="/etc/nginx"
HSTS=""

#Check for a config file
if [ -f ~/.nginx-le-setup ];then
    . ~/.nginx-le-setup
fi

domains=$(find ${NGINX_DIR} -type f -print0 | xargs -0 egrep '^(\s|\t)*server_name' \
		 | sed -r 's/(.*server_name\s*|;)//g' | grep -v "localhost\|_")

add_vhost()
{
    render_template static.template > "${NGINX_DIR}/sites-available/${VNAME}"
    ln -s "${NGINX_DIR}/sites-available/${VNAME}" "${NGINX_DIR}/sites-enabled/${VNAME}"
}

# render a template configuration file
# expand variables + preserve formatting
render_template() {
    eval "echo \"$(cat "$1")\""
}

usage ()
{
echo "Usage: $0 <add|list> <params>"
echo -e "\nCreate/Add arguments\n  -n, \t--name"
echo -e "  -d, \t--directory"
echo -e "  -p, \t--port \t\tPort used for a dynamic website"
echo -e "  -e, \t--email \tlets encrypt email"
echo -e "  -wb, \t--webroot-path"
echo -e "  -y\t\t\tAssume Yes to all queries and do not prompt"
}

create ()
{

    while [[ $# -gt 0 ]]
    do
	key="$1"
	case $key in
	    -n|--name)
		VNAME="$2"
		shift
		;;
	    -d|--dir|--directory)
		VPATH="$2"
		shift
		;;
	    -p|--port)
		VPORT="$2"
		shift
		;;
	    -e|--email)
		EMAIL="$2"
		shift
		;;
	    -wb|--webroot-path)
		WEBROOT_PATH="$2"
		shift
		;;
	    -y)
		CONFIRM=1
		;;
	    *)
		# unknown option
		;;
    esac
    shift # past argument or value
    done

    if [[ -z "$VNAME" ]]; then
	echo "--name required" && exit 1
    elif [[ -z "$VPATH" ]] && [[ -z "$VPORT" ]]; then
	echo "directory or port is needed !" && exit 1
    elif [[ -z "$EMAIL" ]]; then
	echo "email needed for lets encrypt is not set !" && usage && exit 1
    elif [[ -z "${WEBROOT_PATH}" ]]; then
	echo "web root path is not set !" && usage && exit 1
    elif [[ ! -z "$VPATH" ]] && [[ ! -z "$VPORT" ]]; then
	echo "--port and --directory are mutually exclusive"  && exit 1
    else
	for domain in $domains; do
	    if [[ "${domain}" == "${VNAME}" ]]; then
		echo "Error : Domain already listed in nginx's virtual hosts"
		exit 2;
	    fi
	done
    fi

    if [[ ! -d "${WEBROOT_PATH}" ]]; then
	echo "Error : Webroot path '${WEBROOT_PATH}' does not exists"
	exit 3
    fi
    if [[ ! -z "$VPATH" ]] && [[ ! -d "${VPATH}" ]]; then
	echo "Error : directory '${VPATH}' does not exists"
	exit 3
    fi
    if [[ ! -z "$VPORT" ]] && [[ "$VPORT" != ?(-)+([0-9]) ]]; then
	echo "Error : '${VPORT}' is not a valid port"
	exit 3
    fi

    if nginx -t; then
	echo "Creating a virtual host named '${VNAME}'"
    else
	echo "Nginx configuration is incorrect, aborting."
	exit 10;
    fi

    if [[ $CONFIRM == 0 ]]; then
	echo -n "Is this ok?? [y/N]: "
	read continue
	if [[ ${continue} != "y" ]]; then
	    echo "Opertion aborted"
	    exit 3;
	fi
    fi

    echo "Creating certificate...."
    # Creating cert (--staging --debug for testing)
    letsencrypt certonly --rsa-key-size 4096 --non-interactive --agree-tos --keep \
      --text --email "${EMAIL}" -a webroot --webroot-path="${WEBROOT_PATH}" \
      -d "${VNAME}"  || (echo "Error when creating cert, aborting..." && exit 4 )

    # Adding virtual host
    if [ ! -z "${VPATH}" ]; then
	echo "Adding vhost file (static)"
	render_template static.template > "${NGINX_DIR}/sites-available/${VNAME}"
    else
	echo "Adding vhost file (dynamic)"
	render_template dynamic.template > "${NGINX_DIR}/sites-available/${VNAME}"
    fi
    ln -s "${NGINX_DIR}/sites-available/${VNAME}" "${NGINX_DIR}/sites-enabled/${VNAME}"

    # Reload nginx
    if nginx -t; then
	systemctl reload nginx
	echo "${VNAME} is now active and working"
    else
	echo "nginx config verification failed, rollbacking.."
	unlink "${NGINX_DIR}/sites-enabled/${VNAME}"
	rm -v "${NGINX_DIR}/sites-available/${VNAME}"
    fi
}

key="$1"

case $key in
    list)
	echo "$domains"
	;;
    create|add)
	shift
	create "$@"
	;;
    *)
	# unknown option, redirect to "create" by default
	create "$@"
	;;
esac
