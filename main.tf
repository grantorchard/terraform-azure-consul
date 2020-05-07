provider "azurerm" {
  features {}
}

data azurerm_subscription "primary" {}

locals {
}

data azurerm_image "this" {
  name_regex          = "^consul-1.7.2"
  resource_group_name = "packerdependencies"
  sort_descending = true
}

resource azurerm_resource_group "this" {
  name     = var.deployment_name
  location = var.location
}

resource azurerm_virtual_network "this" {
  name                = var.deployment_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource azurerm_subnet "this" {
  name                 = var.deployment_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes       = ["10.0.2.0/24"]
}

resource azurerm_public_ip "this" {
  name                = var.deployment_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource azurerm_role_definition "this" {

  name               = var.deployment_name
  scope              = data.azurerm_subscription.primary.id

  permissions {
    actions     = [
      "Microsoft.Compute/virtualMachineScaleSets/*/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.primary.id,
  ]
}

resource azurerm_role_assignment "this" {
  scope              = data.azurerm_subscription.primary.id
  role_definition_id = azurerm_role_definition.this.id
  principal_id       = azurerm_linux_virtual_machine_scale_set.this.identity[0].principal_id
}



data "template_cloudinit_config" "this" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content      = templatefile("${path.module}/templates/userdata.yaml", {
                      consul_conf = base64encode(templatefile("${path.module}/templates/config.json", {
                        consul_datacenter = var.consul_datacenter
                      })),
                      arm_subscription_id = var.arm_subscription_id
                      arm_tenant_id = var.arm_tenant_id
                      resource_group = var.deployment_name
                      vm_scale_set = var.deployment_name
    })
  }
}

resource azurerm_linux_virtual_machine_scale_set "this" {
  name                = "consul"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Standard_F2"
  instances           = 3
  admin_username      = var.admin_username

  identity {
    type = "SystemAssigned"
  }

  custom_data = data.template_cloudinit_config.this.rendered

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.public_key_location)
  }

  source_image_id = data.azurerm_image.this.id

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "private"
    primary = true
    network_security_group_id = azurerm_network_security_group.this.id
    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.this.id

      public_ip_address {
        name = azurerm_public_ip.this.name
      }
    }
  }
}

resource azurerm_network_security_group "this" {
  name                = var.deployment_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "test123"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = format("%s/32", data.http.this.body)
    destination_address_prefix = "10.0.2.0/24"
  }
}

data http "this" {
  url = "https://ipv4bot.whatismyipaddress.com"
  request_headers = {
    Accept = "application/json"
  }
}
