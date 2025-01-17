#!/bin/bash

function check_utils {

	#
	# https://stackoverflow.com/a/677212
	#

	for util in "${@}"
	do
		command -v ${util} >/dev/null 2>&1 || { echo >&2 "The utility ${util} is not installed."; exit 1; }
	done
}

function configure_tomcat {
	printf "\nCATALINA_OPTS=\"\${CATALINA_OPTS} \${LIFERAY_JVM_OPTS}\"" >> ${1}/liferay/tomcat-${2}/bin/setenv.sh
}

function date2 {
	if [ -z ${1+x} ] || [ -z ${2+x} ]
	then
		if [ "$(uname)" == "Darwin" ]
		then
			echo $(/bin/date)
		elif [ -e /bin/date ]
		then
			echo $(/bin/date)
		else
			echo $(/usr/bin/date)
		fi
	else
		if [ "$(uname)" == "Darwin" ]
		then
			echo $(/bin/date -jf "%a %b %e %H:%M:%S %Z %Y" "${1}" "${2}")
		elif [ -e /bin/date ]
		then
			echo $(/bin/date -d "${1}" "${2}")
		else
			echo $(/usr/bin/date -d "${1}" "${2}")
		fi
	fi
}

function get_tomcat_version {
	if [ -e ${1}/tomcat-* ]
	then
		for temp_file_name in `ls ${1}`
		do
			if [[ ${temp_file_name} == tomcat-* ]]
			then
				local liferay_tomcat_version=${temp_file_name#*-}
			fi
		done
	fi

	if [ -z ${liferay_tomcat_version+x} ]
	then
		echo "Unable to determine Tomcat version."

		exit 1
	fi

	echo ${liferay_tomcat_version}
}

function main {
	check_utils 7za curl docker java unzip

	echo "Using"
	echo "\$LIFERAY_DOCKER_LICENSE_FILE=$LIFERAY_DOCKER_LICENSE_FILE"
	echo "\$LIFERAY_DOCKER_FIXPACK_FOLDER=$LIFERAY_DOCKER_FIXPACK_FOLDER"
	echo "\$LIFERAY_DOCKER_PATCHING_TOOL=$LIFERAY_DOCKER_PATCHING_TOOL"
	echo "\$LIFERAY_DOCKER_CUSTOM_RELEASE=$LIFERAY_DOCKER_CUSTOM_RELEASE"
	echo " "

	#
	# Make temporary directory.
	#

	local current_date=$(date "+%Y-%m-%dT%H:%M:%SZ")

	local timestamp=$(date "+%Y%m%d%H%M")

	mkdir -p ${timestamp}

	cp -r template/* ${timestamp}
	cp -r template/.bashrc ${timestamp}

	#
	# Download and prepare release.
	#

	local release_dir=${1%/*}

	release_dir=${release_dir#*com/}
	release_dir=${release_dir#*com/}
	release_dir=${release_dir#*private/ee/}
	release_dir=releases/${release_dir}

	local release_file_name=${1##*/}

	local release_file_url=${1}

	if [[ ${release_file_url} != http://mirrors.lax.liferay.com* ]]
	then
		release_file_url=http://mirrors.lax.liferay.com/${release_file_url}
	fi

	if [ ! -e ${release_dir}/${release_file_name} ]
	then
		echo ""
		echo "Downloading ${release_file_url}."
		echo ""

		mkdir -p ${release_dir}

		curl -o ${release_dir}/${release_file_name} ${release_file_url}
	fi

	if [[ ${release_file_name} == *.7z ]]
	then
		7za x -O${timestamp} ${release_dir}/${release_file_name}
	else
		unzip -q ${release_dir}/${release_file_name} -d ${timestamp}
	fi

	mv ${timestamp}/liferay-* ${timestamp}/liferay

	#
	# Configure Tomcat.
	#

	local liferay_tomcat_version=$(get_tomcat_version ${timestamp}/liferay)

	configure_tomcat ${timestamp} ${liferay_tomcat_version}

	#
	# Warm up Tomcat for older versions to speed up starting Tomcat. Populating
	# the Hypersonic files can take over 20 seconds.
	#

	warm_up_tomcat ${timestamp}

	#
	# Download trial DXP license.
	#

	if [[ ${release_file_name} == *-dxp-* ]]
	then
		if [ -n "${LIFERAY_DOCKER_LICENSE_FILE}" -a -f ${LIFERAY_DOCKER_LICENSE_FILE} ]
		then
			mkdir -p ${timestamp}/liferay/osgi/modules

			cp -v ${LIFERAY_DOCKER_LICENSE_FILE} ${timestamp}/liferay/osgi/modules

		elif [ -z "${LIFERAY_DOCKER_LICENSE_CMD}" ]
		then
			echo "Please set the environment variable LIFERAY_DOCKER_LICENSE_CMD to generate a trial DXP license."

			exit 1
		else
			mkdir -p ${timestamp}/liferay/deploy

			license_file_name=license-$(date "${current_date}" "+%Y%m%d").xml

			eval "curl --silent --header \"${LIFERAY_DOCKER_LICENSE_CMD}?licenseLifetime=$(expr 1000 \* 60 \* 60 \* 24 \* 30)&startDate=$(date "${current_date}" "+%Y-%m-%d")&owner=ci%40wedeploy.com\" > ${timestamp}/liferay/deploy/${license_file_name}"

			sed -i "s/\\\n//g" ${timestamp}/liferay/deploy/${license_file_name}
			sed -i "s/\\\t//g" ${timestamp}/liferay/deploy/${license_file_name}
			sed -i "s/\"<?xml/<?xml/" ${timestamp}/liferay/deploy/${license_file_name}
			sed -i "s/license>\"/license>/" ${timestamp}/liferay/deploy/${license_file_name}
			sed -i 's/\\"/\"/g' ${timestamp}/liferay/deploy/${license_file_name}
			sed -i 's/\\\//\//g' ${timestamp}/liferay/deploy/${license_file_name}

			if [ ! -e ${timestamp}/liferay/deploy/${license_file_name} ]
			then
				echo "Trial DXP license does not exist at ${timestamp}/liferay/deploy/${license_file_name}."

				exit 1
			else
				echo "Trial DXP license exists at ${timestamp}/liferay/deploy/${license_file_name}."

				#exit 1
			fi
		fi
	fi

	#
	# Run Patching Tool
	#
	if [[ ${release_file_name} == *-dxp-* ]]
	then
		if [ -n "${LIFERAY_DOCKER_PATCHING_TOOL}" -a -f ${LIFERAY_DOCKER_PATCHING_TOOL} ]
		then
			echo "Update Pathing tool: ${LIFERAY_DOCKER_PATCHING_TOOL}"

			mv ${timestamp}/liferay/patching-tool ${timestamp}/liferay/patching-tool.old

			unzip -q ${LIFERAY_DOCKER_PATCHING_TOOL} -d ${timestamp}/liferay

			cp ${timestamp}/liferay/patching-tool.old/default.properties ${timestamp}/liferay/patching-tool

			cp -v ${timestamp}/liferay/patching-tool.old/patches/*.zip ${timestamp}/liferay/patching-tool/patches

			rm -rf ${timestamp}/liferay/patching-tool.old
		else
			echo "Use LIFERAY_DOCKER_PATCHING_TOOL environment to point a new PatchingTool distribution"
		fi

		if [ -n "${LIFERAY_DOCKER_FIXPACK_FOLDER}" -a -d ${LIFERAY_DOCKER_FIXPACK_FOLDER} ]
		then
			echo "Run Patching Tool"

			if [ -f ${LIFERAY_DOCKER_FIXPACK_FOLDER}/module-mapping.txt ]
			then
				cp -v ${LIFERAY_DOCKER_FIXPACK_FOLDER}/module-mapping.txt ${timestamp}/liferay/patching-tool
			fi

			cp -v ${LIFERAY_DOCKER_FIXPACK_FOLDER}/*.zip ${timestamp}/liferay/patching-tool/patches

			chmod +x ${timestamp}/liferay/patching-tool/patching-tool.sh

			bash ${timestamp}/liferay/patching-tool/patching-tool.sh install
		else
			echo "Set LIFERAY_DOCKER_FIXPACK_FOLDER environment to set folder with FixPack or HotFix to install"
		fi
	fi


	#
	# Build Docker image.
	#

	local docker_image_name
	local label_name

	if [[ ${release_file_name} == *-commerce-* ]]
	then
		docker_image_name="commerce"
		label_name="Liferay Commerce"
	elif [[ ${release_file_name} == *-dxp-* ]] || [[ ${release_file_name} == *-private* ]]
	then
		docker_image_name="dxp"
		label_name="Liferay DXP"
	elif [[ ${release_file_name} == *-portal-* ]]
	then
		docker_image_name="portal"
		label_name="Liferay Portal"
	else
		echo "${release_file_name} is an unsupported release file name."

		exit 1
	fi

	if [[ ${release_file_url%} == */snapshot-* ]]
	then
		docker_image_name=${docker_image_name}-snapshot
	fi

	local release_version=${release_file_url%/*}

	release_version=${release_version##*/}

	local label_version=${release_version}

	if [[ ${release_file_url%} == */snapshot-* ]]
	then
		local release_branch=${release_file_url%/*}

		release_branch=${release_branch%/*}
		release_branch=${release_branch%-private*}
		release_branch=${release_branch##*-}

		local release_hash=$(cat ${timestamp}/liferay/.githash)

		release_hash=${release_hash:0:7}

		if [[ ${release_branch} == master ]]
		then
			label_version="Master Snapshot on ${label_version} at ${release_hash}"
		else
			label_version="${release_branch} Snapshot on ${label_version} at ${release_hash}"
		fi
	fi

	local docker_image_tags=()

	if [[ ${release_file_url%} == */snapshot-* ]]
	then
		docker_image_tags+=("liferay/${docker_image_name}:${release_branch}-${release_version}-${release_hash}")
		docker_image_tags+=("liferay/${docker_image_name}:${release_branch}-$(date "${current_date}" "+%Y%m%d")")
		docker_image_tags+=("liferay/${docker_image_name}:${release_branch}")

	elif [ -n "${LIFERAY_DOCKER_CUSTOM_RELEASE}" ]
	then
		echo "Use custom release version ${LIFERAY_DOCKER_CUSTOM_RELEASE}"

		docker_image_tags+=("liferay/${docker_image_name}:${LIFERAY_DOCKER_CUSTOM_RELEASE}-${timestamp}")
		docker_image_tags+=("liferay/${docker_image_name}:${LIFERAY_DOCKER_CUSTOM_RELEASE}")

	else
		docker_image_tags+=("liferay/${docker_image_name}:${release_version}-${timestamp}")
		docker_image_tags+=("liferay/${docker_image_name}:${release_version}")
	fi

	local docker_image_tags_args=""

	for docker_image_tag in "${docker_image_tags[@]}"
	do
		docker_image_tags_args="${docker_image_tags_args} --tag ${docker_image_tag}"
	done

	docker build \
		--build-arg LABEL_BUILD_DATE="${current_date}" \
		--build-arg LABEL_NAME="${label_name}" \
		--build-arg LABEL_VCS_REF=$(git rev-parse HEAD) \
		--build-arg LABEL_VERSION="${label_version}" \
		--build-arg LIFERAY_TOMCAT_VERSION=${liferay_tomcat_version} \
		$(echo ${docker_image_tags_args}) \
		${timestamp}

	#
	# Push Docker image.
	#

	for docker_image_tag in "${docker_image_tags[@]}"
	do
		echo "**"
		echo "** Docker Push Disabled "
		echo "**"
		#docker push ${docker_image_tag}
	done

	#
	# Clean up temporary directory.
	#

	rm -fr ${timestamp}
}

function start_tomcat {
	local timestamp=${1}

	./${timestamp}/liferay/tomcat-*/bin/catalina.sh start

	until $(curl --head --fail --output /dev/null --silent http://localhost:8080)
	do
		sleep 3
	done

	./${timestamp}/liferay/tomcat-*/bin/catalina.sh stop

	local kill_tries=5
	local tries=0
	while [ "$(running_tomcat)" -ge 1 ]
	do
		sleep 5

		if [ $kill_tries -gt 0 ]
		then
			tries=$((tries+1))
			if [ $tries -ge $kill_tries ]
			then
				P=$(running_tomcat_pid)

				kill -9 $P
			fi
		fi
	done

	rm -fr ${timestamp}/liferay/data/osgi/state
	rm -fr ${timestamp}/liferay/osgi/state
	rm -fr ${timestamp}/liferay/tomcat-*/logs/*
}

function running_tomcat {
    ps -C java -f | grep -c ${timestamp}/liferay/tomcat-*/bin
}

function running_tomcat_pid {
    ps -C java -f | grep ${timestamp}/liferay/tomcat-*/bin | while read a b c; do echo -e "$b \c"; done
}

function stat {
	if [ "$(uname)" == "Darwin" ]
	then
		echo $(/usr/bin/stat -f "%z" "${1}")
	else
		echo $(/usr/bin/stat --printf="%s" "${1}")
	fi
}

function warm_up_tomcat {
	local timestamp=${1}

	if [ -d ${timestamp}/liferay/data/hsql ]
	then
		if [ $(stat ${timestamp}/liferay/data/hsql/lportal.script) -lt 1024000 ]
		then
			start_tomcat ${timestamp}
		else
			echo Tomcat is already warmed up.
		fi
	fi

	if [ -d ${timestamp}/liferay/data/hypersonic ]
	then
		if [ $(stat ${timestamp}/liferay/data/hypersonic/lportal.script) -lt 1024000 ]
		then
			start_tomcat ${timestamp}
		else
			echo Tomcat is already warmed up.
		fi
	fi
}

main ${1}
