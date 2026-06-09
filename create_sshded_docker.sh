#!/bin/sh
set -x

IMAGE_NAME="ubuntu:24.04"
SSHDED_IMAGE="lwn_sshded_"${IMAGE_NAME//:/_}

DOCKER_NAME="lwn_"${IMAGE_NAME//:/_}
DOCKER_NAME="my_ubuntu"
SSH_PORT_IN_CONTAINER=26211
ROOT_PASSWD="root"

CUSTOM_USER_NAME="lwn"



if [ ! -f ~/.ssh/id_ed25519.pub ]; then
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
fi
SSH_PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)


cat > Dockerfile << EOF
#设置继承镜像
FROM ${IMAGE_NAME}

WORKDIR .

RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list
RUN sed -i 's@//ports.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get update

RUN DEBIAN_FRONTEND=noninteractive apt install -y tzdata

#安装ssh服务
RUN apt-get install -y passwd openssh-server

RUN mkdir -p /var/run/sshd
RUN sed -i 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config
RUN sed -i "s/.*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config

RUN apt install -y vim git net-tools sudo

#设置初始密码
RUN echo "root:${ROOT_PASSWD}"|chpasswd

# 免密sudo
RUN useradd -m -s /bin/bash ${CUSTOM_USER_NAME}
RUN usermod -aG sudo ${CUSTOM_USER_NAME}
RUN echo "${CUSTOM_USER_NAME}:${ROOT_PASSWD}" | chpasswd
RUN mkdir -p /etc/sudoers.d
RUN echo "${CUSTOM_USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${CUSTOM_USER_NAME}
RUN chmod 0440 /etc/sudoers.d/${CUSTOM_USER_NAME}

RUN apt install python3
COPY systemctl3.py /usr/bin/systemctl
RUN chmod a+x /usr/bin/systemctl


#开放端口
EXPOSE 22
#设置自启动命令
ENTRYPOINT /usr/bin/systemctl -1

EOF

wget https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/refs/heads/v1.7/files/docker/systemctl3.py

docker pull ${IMAGE_NAME}

docker build --network host -t ${SSHDED_IMAGE} .

docker rm -f ${DOCKER_NAME}

# --shm-size=1g这个flag为了支持nccl。nccl库需要很大的共享内存
# https://github.com/NVIDIA/nccl-tests/issues/143
docker run \
         -d \
         --restart=always \
         -v $(pwd):/home/${CUSTOM_USER_NAME}:rw \
         --name ${DOCKER_NAME} \
         --hostname "${DOCKER_NAME}_docker" \
         -p ${SSH_PORT_IN_CONTAINER}:22 \
         --network to_brlan \
         --shm-size=1g \
         ${SSHDED_IMAGE}

docker exec ${DOCKER_NAME} mkdir -p /home/${CUSTOM_USER_NAME}/.ssh
docker cp ~/.ssh/id_ed25519.pub ${DOCKER_NAME}:/home/${CUSTOM_USER_NAME}/.ssh/authorized_keys
docker exec ${DOCKER_NAME} chown ${CUSTOM_USER_NAME}:${CUSTOM_USER_NAME} /home/${CUSTOM_USER_NAME}/.ssh/authorized_keys

