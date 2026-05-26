
FROM registry.access.redhat.com/ubi10/python-314-minimal:10.2-1779774002@sha256:36fb2f81e7364634ebf1f0aaef4625a28083fa756f66ae896c62b22150d9420a AS prod

LABEL konflux.additional-tags="0.6.0"

USER 0

# Standard path variables
ENV HOME="/home/app" \
    APP="/home/app/src"

# Terraform versions and other related variables
ENV TF_VERSION="1.13.4" \
    TF_PLUGIN_CACHE_DIR=${HOME}/.terraform.d/plugin-cache/ \
    TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true

COPY LICENSE /licenses/LICENSE

# Install dependencies
RUN INSTALL_PKGS="make tar shadow-utils which unzip" && \
    microdnf -y --nodocs --setopt=install_weak_deps=0 install $INSTALL_PKGS && \
    microdnf clean all && \
    rm -rf /var/cache/yum*

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
