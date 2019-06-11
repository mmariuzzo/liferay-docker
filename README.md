# LIFERAY DOCKER IMAGE BUILDER

Made some changes to:
* support RHEL/CentOS (I haven't tested other OS)
* kill tomcat if it doesn't stop after 25 seconds
* use an already downloaded license file.<br/>File have to be pointed by ```LIFERAY_DOCKER_LICENSE_FILE``` environment variable.
* upgrade PatchingTool tool.<br/>Use ```LIFERAY_DOCKER_PATCHING_TOOL``` environment variable to point to new pathing-tool zip
* apply fixpack or hotfix.<br/>Use ```LIFERAY_DOCKER_PATCHES_FOLDER``` environment variable to identity folder with the fixpacks or hotfix to install
* define a custom release name.<br/>Use ```LIFERAY_DOCKER_CUSTOM_RELEASE``` environment variable to set it 



### Example

Suppose you have a regular Liferay Subscription and want to create a Liferay 7.1 DXP image with FixPack 11.
You have to:

* go inside my ```rhel-centos``` branch

  ```console
  $ git clone https://github.com/mmariuzzo/liferay-docker
  $ cd liferay-docker
  $ git checkout rhel-centos
  ```

* create a folder to place Liferay 7.1 DXP sp2 Tomcat Bundle (the bundle you want to start from)

  ```console
  $ mkdir -p releases/portal/7.1.10.2
  ```

* grab the tomcat bundle from Liferay site and place inside it. The file is named ```liferay-dxp-tomcat-7.1.10.2-sp2-20190422172027516.zip```

* create a forder name ```extras``` and place you licence xml inside it

  ```console
  $ mkdir extras
  ```

* grab the latest version of PatchingTool from Liferay site and place inside it. The actual latest version is named ```patching-tool-2.0.12.zip```.

* create a folder to host fixpack and hotfix

  ```console
  $ mkdir -p extras/patches
  ```

* grab the required fixpack from Liferay site and place inside that folder. Actually we have only ```liferay-fix-pack-dxp-11-7110.zip```.

* set the required environment variables

  ```console
  $ export LIFERAY_DOCKER_LICENSE_FILE=/path/to/liferay-docker/extras/activation-key-xyz.xml
  $ export LIFERAY_DOCKER_FIXPACK_FOLDER=/path/to/liferay-docker/extras/patches
  $ export LIFERAY_DOCKER_PATCHING_TOOL=/path/to/liferay-docker/extras/patching-tool-2.0.12.zip
  $ export LIFERAY_DOCKER_CUSTOM_RELEASE=7.1.10.fp11
  ```

* run the image creation using original Liferay repository url (local file will be used instead)

  ```console
  $ bash build_image.sh files.liferay.com/private/ee/portal/7.1.10.2/liferay-dxp-tomcat-7.1.10.2-sp2-20190422172027516.zip
  ```

  

