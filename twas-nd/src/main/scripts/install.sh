#!/bin/sh

#      Copyright (c) Microsoft Corporation.
# 
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
# 
#           http://www.apache.org/licenses/LICENSE-2.0
# 
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

while getopts "u:p:" opt; do
    case $opt in
        u)
            userName=$OPTARG #IBM user id for downloading artifacts from IBM web site
        ;;
        p)
            password=$OPTARG #password of IBM user id for downloading artifacts from IBM web site
        ;;
    esac
done

# Wait untile the data disk is partitioned and mounted
output=$(df -h)
while echo $output | grep -qv "/datadrive"
do
    sleep 10
    echo "Waiting for data disk partition & moute complete..."
    output=$(df -h)
done
name=$(df -h | grep "/datadrive" | awk '{print $1;}' | grep -Po "(?<=\/dev\/).*")
echo "UUID=$(blkid | grep -Po "(?<=\/dev\/${name}\: UUID=\")[^\"]*(?=\".*)")   /datadrive   xfs   defaults,nofail   1   2" >> /etc/fstab

# Move tWAS installation properties file to /datadrive
mv virtualimage.properties /datadrive

# Get tWAS installation properties
source /datadrive/virtualimage.properties

# Create installation directories
mkdir -p ${IM_INSTALL_DIRECTORY} && mkdir -p ${WAS_ND_INSTALL_DIRECTORY} && mkdir -p ${IM_SHARED_DIRECTORY}

# Install IBM Installation Manager
wget -O "$IM_INSTALL_KIT" "$IM_INSTALL_KIT_URL" -q
mkdir im_installer
unzip -q "$IM_INSTALL_KIT" -d im_installer
./im_installer/userinstc -log log_file -acceptLicense -installationDirectory ${IM_INSTALL_DIRECTORY}

# Save credentials to a secure storage file
${IM_INSTALL_DIRECTORY}/eclipse/tools/imutilsc saveCredential -secureStorageFile storage_file \
    -userName "$userName" -userPassword "$password" -passportAdvantage

# Install IBM WebSphere Application Server Network Deployment V9 using IBM Instalation Manager
${IM_INSTALL_DIRECTORY}/eclipse/tools/imcl install "$WAS_ND_TRADITIONAL" "$IBM_JAVA_SDK" -repositories "$REPOSITORY_URL" \
    -installationDirectory ${WAS_ND_INSTALL_DIRECTORY}/ -sharedResourcesDirectory ${IM_SHARED_DIRECTORY}/ \
    -secureStorageFile storage_file -acceptLicense -preferences $SSL_PREF,$DOWNLOAD_PREF -showProgress

# Create standalone application profile
${WAS_ND_INSTALL_DIRECTORY}/bin/manageprofiles.sh -create -profileName AppSrv1 -templatePath ${WAS_ND_INSTALL_DIRECTORY}/profileTemplates/default \
    -hostName $(hostname) -nodeName $(hostname)Node01

# Create and start server
${WAS_ND_INSTALL_DIRECTORY}/profiles/AppSrv1/bin/startServer.sh server1

# Open ports by adding iptables rules
firewall-cmd --zone=public --add-port=9060/tcp --permanent
firewall-cmd --zone=public --add-port=9080/tcp --permanent
firewall-cmd --zone=public --add-port=9043/tcp --permanent
firewall-cmd --zone=public --add-port=9443/tcp --permanent
firewall-cmd --zone=public --add-port=8880/tcp --permanent
firewall-cmd --reload

# Remove temporary files
rm -rf storage_file && rm -rf log_file
