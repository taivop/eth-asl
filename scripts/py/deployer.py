"""A deployer class to deploy a template on Azure"""
import json
import logging
from colors import Colors
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.resource.resources.models import DeploymentMode
from azure.common.credentials import UserPassCredentials
from azure.mgmt.resource.resources.operations import ResourceGroupsOperations


class Deployer(object):
    def __init__(self, resource_group, template_path, parameters,
                 user_email="sinep@sq42nahotmail.onmicrosoft.com",
                 user_password="4D0$1QcK5:Nsn:jd!'1j4Uw'j*",
                 subscription_id="0003c64e-455e-4794-8665-a59c04a8961b"):
        # region ---- Set instance fields ----
        self.resource_group = resource_group
        self.deployment_name = "taivo_foo_deployment"
        self.template_path = template_path
        self.parameters = parameters

        self.credentials = UserPassCredentials(user_email, user_password)
        self.client = ResourceManagementClient(self.credentials, subscription_id)
        # endregion

        # region ---- Set up logging ----
        LOG_FORMAT = '%(asctime)-15s %(message)s'
        LOG_LEVEL = logging.INFO
        formatter = logging.Formatter(LOG_FORMAT)

        ch = logging.StreamHandler()
        ch.setLevel(LOG_LEVEL)
        ch.setFormatter(formatter)

        self.log = logging.getLogger(__name__)
        self.log.setLevel(LOG_LEVEL)
        self.log.addHandler(ch)
        # endregion

    def deploy(self):
        """Deploy the template to a resource group."""

        self.log.info("Initializing Deployer class with resource group '{}' and template at '{}'."
                      .format(self.resource_group, self.template_path))
        self.log.info("Parameters: " + str(self.parameters))
        self.client.resource_groups.create_or_update(
            self.resource_group, {'location': 'westeurope'}
        )

        with open(self.template_path, 'r') as template_file_fd:
            template = json.load(template_file_fd)

        parameters = {k: {'value': v} for k, v in self.parameters.items()}

        deployment_properties = {
            'mode': DeploymentMode.complete,
            'template': template,
            'parameters': parameters
        }

        already_exists = self.client.resource_groups.check_existence(self.resource_group)
        if already_exists:
            self.log.info("Resource group already exists:")
            resources = self.client.resource_groups.list_resources(self.resource_group)
            for res in resources:
                self.log.info(Deployer.stringify_resource_group(res))
        else:
            self.log.info("Resource group does not exist yet.")

        input("waiting")

        deployment_async_operation = self.client.deployments.create_or_update(
            self.resource_group,
            self.deployment_name,
            deployment_properties
        )

        self.log.info("Started deployment of resource group {}.".format(self.resource_group))

        return deployment_async_operation

    def deploy_wait(self):
        """Convenience method that blocks until deployment is done."""
        deployment_async_operation = self.deploy()
        deployment_async_operation.wait()
        self.log.info("Deployment complete, resource group {} created.".format(self.resource_group))

    def destroy(self):
        """Destroy the given resource group"""
        self.log.info("Destroying resource group {}...".format(self.resource_group))
        deletion_async_operation = self.client.resource_groups.delete(self.resource_group)
        self.log.info("Started deletion of resource group {}.".format(self.resource_group))

        return deletion_async_operation

    def destroy_wait(self):
        """Convenience method that blocks until deletion is done."""
        deletion_async_operation = self.destroy()
        deletion_async_operation.wait()
        self.log.info("Resource group {} destroyed.".format(self.resource_group))

    @staticmethod
    def kill(resource_group):
        """Kill the given resource group."""
        print("Killing resource group {}...".format(resource_group))
        d = Deployer(None, None, None)
        deletion_async_operation = d.client.resource_groups.delete(resource_group)
        print("Started killing resource group {}.".format(resource_group))

        return deletion_async_operation

    @staticmethod
    def kill_wait(resource_group):
        deletion_async_operation = Deployer.kill(resource_group)
        deletion_async_operation.wait()
        print("Resource group {} destroyed.".format(resource_group))

    @staticmethod
    def stringify_properties(props):
        """Print a ResourceGroup properties instance."""
        s = ""
        if props and props.provisioning_state:
            s += "\tProperties:\n"
            s += "\t\tProvisioning State: {}\n".format(props.provisioning_state)
        s += "\n"
        return s

    @staticmethod
    def stringify_resource_group(group):
        """Print a ResourceGroup instance."""
        s = ""
        s += "\tName: {}\n".format(Colors.ok_blue(Colors.bold(group.name)))
        s += "\tId: {}\n".format(group.id)
        s += "\tLocation: {}\n".format(group.location)
        s += "\tTags: {}\n".format(group.tags)
        s += Deployer.stringify_properties(group.properties)
        return s
