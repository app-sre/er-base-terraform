# Overview

External resources base image with Terraform. This image is not intended to be directly used as a final module, it should be used as a base for defining final Terraform based modules.

Using common images on modules using the same provider saves a ton of bandwith by reeducing the number of required layers.

## Notes for Final modules

* The Terraform entrypoint must be set in the `./module` path.
* entrypoint.sh runs `python generate-tf-config` call to generate the terraform config required to run the module. This script call
  must be implemented in the final module. It should generate the backend configuration and the variables file to be used by the module.
* [er-aws-kms](https://github.com/app-sre/er-aws-kms) is a good example to get started.
* [external-resources-io](https://github.com/app-sre/external-resources-io) has helper methods to generate the configuration files (>=0.4.0).

