
FROM registry.access.redhat.com/ubi10/python-314-minimal@sha256:ee3ee7060695da0bc102a0dc523b76ae4332daf5909ef2f01a07d6feccd9bab2 AS prod

LABEL konflux.additional-tags="0.6.0"

USER 0

# Standard path variables
ENV APP_ROOT=/opt/app-root \
    APP=/opt/app-root/src \
    USER=1001

# Python and UV related variables
ENV \
    # unbuffered output for easier logging
    PYTHONUNBUFFERED=1 \
    # use venv from ubi image
    UV_PROJECT_ENVIRONMENT=${APP_ROOT} \
    # compile bytecode for faster startup
    UV_COMPILE_BYTECODE="true" \
    # disable uv cache. it doesn't make sense in a container
    UV_NO_CACHE=true \
    BASH_ENV="${APP_ROOT}/bin/activate" \
    ENV="${APP_ROOT}/bin/activate" \
    PROMPT_COMMAND=". ${APP_ROOT}/bin/activate"

# Terraform versions and other related variables
ENV TF_VERSION="1.13.4" \
    TF_PLUGIN_CACHE_DIR=${HOME}/.terraform.d/plugin-cache/ \
    TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true

COPY LICENSE /licenses/LICENSE

# Install dependencies
RUN INSTALL_PKGS="make tar which unzip" && \
    microdnf -y --nodocs --setopt=install_weak_deps=0 install $INSTALL_PKGS && \
    microdnf clean all && \
    rm -rf /var/cache/yum*

# Install Terraform
ARG TARGETARCH
RUN curl -sfL https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TARGETARCH}.zip \
    -o terraform.zip && \
    unzip terraform.zip && \
    mv terraform /usr/local/bin/terraform && \
    rm terraform.zip

RUN mkdir -p ${TF_PLUGIN_CACHE_DIR} && chown 1001:0 ${TF_PLUGIN_CACHE_DIR}

# Clean up /tmp
RUN rm -rf /tmp && mkdir /tmp && chmod 1777 /tmp

COPY terraform-provider-sync /usr/local/bin/terraform-provider-sync

USER ${USER}

COPY entrypoint.sh ./
ENTRYPOINT [ "bash", "entrypoint.sh" ]

FROM prod AS test
COPY Makefile ./
RUN make test
