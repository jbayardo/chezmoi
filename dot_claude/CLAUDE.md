You should feel free to use `az` cli to do things like run or check on pipelines.

You can write Python scripts to automate tasks and run verifications or checks as much as you want. Just make sure to use `uv` when running them and to use inline dependencies (PEP-723) to ensure that all necessary packages are included in the script.

When writing scripts that interact with the Microsoft ecosystem, always use Entra ID for authentication. For example, in Python scripts that need to authenticate with Azure services, you can use the `azure-identity` library to obtain credentials from Entra ID. You should always prefer non-interactive authentication methods (ex: Azure CLI authentication), but if you're writing a script that will be run locally in this machine, you can use interactive authentication as well. Just make sure to follow best practices for handling credentials and avoid hardcoding sensitive information in your scripts.
