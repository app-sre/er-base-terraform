
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.6-1754456323@sha256:e6b39b0a2cd88c0d904552eee0dca461bc74fe86fda3648ca4f8150913c79d0f AS prod

LABEL konflux.additional-tags="0.3.8"

USER 0

# Standard path variables
ENV HOME="/home/app" \
    APP="/home/app/src"

# Terraform versions and other related variables
ENV TF_VERSION="1.6.6" \
    TF_PLUGIN_CACHE_DIR=${HOME}/.terraform.d/plugin-cache/ \
    TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true

COPY LICENSE /licenses/LICENSE

# Install python
RUN microdnf install -y python3.12 && \
    update-alternatives --install /usr/bin/python3 python /usr/bin/python3.12 1 && \
    microdnf clean all && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/yum.*

# Install dependencies
RUN INSTALL_PKGS="make tar which unzip" && \
    microdnf -y --nodocs --setopt=install_weak_deps=0 install $INSTALL_PKGS && \
    microdnf clean all && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/yum.*

# Install Terraform
RUN curl -sfL https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip \
    -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/terraform && \
    rm terraform.zip

RUN mkdir -p ${TF_PLUGIN_CACHE_DIR} && chown 1001:0 ${TF_PLUGIN_CACHE_DIR}

# Clean up /tmp
RUN rm -rf /tmp && mkdir /tmp && chmod 1777 /tmp

COPY terraform-provider-sync /usr/local/bin/terraform-provider-sync

# User setup
RUN useradd -u 1001 -g 0 -d ${HOME} -M -s /sbin/nologin -c "Default Application User" app && \
    chown -R 1001:0 ${HOME}
USER app

WORKDIR ${APP}
COPY entrypoint.sh ./
ENTRYPOINT [ "bash", "entrypoint.sh" ]

FROM prod AS test
COPY Makefile ./
RUN make test
