#!/bin/bash
set -x

IMAGE_NAME="ubuntu:24.04"
SSHDED_IMAGE="lwn_sshded_"${IMAGE_NAME//:/_}

DOCKER_NAME="lwn_"${IMAGE_NAME//:/_}
SSH_PORT_IN_CONTAINER=26211
ROOT_PASSWD="root"

CUSTOM_USER_NAME="lwn"


cat > get_in_${DOCKER_NAME}.sh << EOF
#!/bin/sh
set -x
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "[127.0.0.1]:${SSH_PORT_IN_CONTAINER}"
sshpass -p ${ROOT_PASSWD} ssh -o StrictHostKeyChecking=no -p ${SSH_PORT_IN_CONTAINER} ${CUSTOM_USER_NAME}@127.1
EOF

chmod +x get_in_${DOCKER_NAME}.sh


cat > Dockerfile << EOF
#设置继承镜像
FROM ${IMAGE_NAME}

#提供一些作者的信息
MAINTAINER docker_user (user@docker.com)

#下面开始运行更新命令
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


#开放端口
EXPOSE 22
#设置自启动命令
ENTRYPOINT /usr/sbin/sshd -D

EOF

docker pull ${IMAGE_NAME}

docker build -t ${SSHDED_IMAGE} .

docker rm -f ${DOCKER_NAME}

# --shm-size=1g这个flag为了支持nccl。nccl库需要很大的共享内存
# https://github.com/NVIDIA/nccl-tests/issues/143
docker run \
         -d \
         -v $(pwd):/home/${CUSTOM_USER_NAME} \
         --name ${DOCKER_NAME} \
         --hostname "${DOCKER_NAME}_docker" \
         -p ${SSH_PORT_IN_CONTAINER}:22 \
         ${SSHDED_IMAGE}

         --network host \
         --runtime=nvidia \
         --shm-size=1g \
