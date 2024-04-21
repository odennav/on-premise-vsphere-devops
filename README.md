
# On-Prem DevOps with VMware vSphere

Automate your Self-hosted vSphere datacenter and deploy a fully load-balanced application using Docker, Gogs, Ansible, Vault, Packer, Terraform and Jenkins.

![](https://github.com/odennav/on-prem-devops-vsphere/blob/main/docs/pipeline.png)

## Prerequisites
  
  - Deploy self hosted vSphere datacenter and datacenter cluster with 2 ESXi hosts
  - Enable vSphere HA and vSphere DRS
  - Create datastore cluster and enable Storage DRS
  - Deploy vCenter server appliance on ESXi host.
  - Provision a build-machine on next ESXi host with Ubuntu 20.04
  - Git bash or linux terminal on local machine.
  - Assume IPv4 address of build-machine VM is `192.168.149.8`.


# Getting Started

  Two Pipelines will be implemented:
  - Manual Pipeline
  - Automated Pipeline


## Manual Pipeline

  This workflow involves the following steps:
  - Docker Installation
  - Gogs(source control) Installation and Configuration
  - Vault Installation and Configuration
  - Packer Installation and Configuration
  - Terraform Installation and VM Deployment 
  - Ansible Installation and Machine Configuration


-----

1.  **DOCKER INSTALLATION**

    To install Docker Engine for the first time on build-machine, we'll set up the Docker repository.
    Afterward, we can install and update Docker from the repository.
    
    Add Docker's official GPG key:
    ```bash   
    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    ```
    
    Add the repository to Apt sources:
    
    ```bash
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    ```

    To install the latest version:
    
    ```bash
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin.
    ```
    
    Verify that the Docker Engine installation is successful by running the `hello-world` image.
    ```bash
    sudo docker run hello-world
    ```

    This command downloads a test image and runs it in a container. When the container runs, it prints a confirmation message and exits.

    You have now successfully installed and started Docker Engine.


-----

2.  **GOGS INSTALLATION and CONFIGURATION**
    
    Build a simple, stable and extensible self-hosted Git service.

    Pull image from Docker Hub.
    ```bash
    docker pull gogs/gogs
    ```
    
    Create local directory for volume.
    ```bash    
    mkdir -p /opt/gogs
    ```

    Use `docker run` for the first time.
    ```bash
    docker run --name gogs --restart always -p 10022:22 -p 3880:3000 -v /opt/gogs:/data gogs/gogs
    ```

    It is important to map the SSH service from the container to the host and set the appropriate SSH Port and URI settings when setting up Gogs for the first time. 

    To access and clone Git repositories with the above configuration you would use: 
    ```bash
    git clone ssh://git@192.168.149.8:10022/odennav/on-prem-devops-vsphere.git
    ```

    Files will be store in local path of build-machine instance,  /opt/gogs in my case.
    

    For first-time run installation, install gogs with mysqllite3 

    Initialize local repository and create README
    ```bash
    git init
    touch README.md
    echo "Hello Gogs!" > README.md
    ```

    ```bash
    git config --global user.email "odennav@odennav.com"
    git config --global user.name "odennav"
    git config --global credentials.helper store
    ```
   
    Add all changes to staging area and commit
    ```bash
    git add .
    git commit -m "first commit"
    ```

    Connect local repo with remote repository
    ```bash
    git remote add origin https://192.168.149.8:3880/odennav/on-prem-devops-vsphere.git
    ```

    Push commits to remote repository
    ```bash
    git push -u origin master
    ```

    Set tracking information for this branch
    ```bash
    git branch --set-upstream-to=origin/master master
    ```

-----

3. **VAULT INSTALLATION and CONFIGURATION**

   Install jq to format the JSON output for vault
   ```bash
   sudo apt-get install jq -y
   ```

   Secure, store, and tightly control access to tokens, passwords, certificates, and encryption keys in modern computing.
   Protects secrets and other sensitive data using a UI, CLI, or HTTP API.
   
    Create the vault to generate unseal and root tokens. 
    Unseal the vault. 
      - 5 Unseal keys are created upon a vault initialization.
      -	3 Unseal keys are required to unseal the vault.	
    Push secure credentials and store.`
    Pull secure credentials through an API for an app at runtime.

    
    Install the HashiCorp GPG key, verify the key's fingerprint, and install Vault.
    
    Update the package manager and install GPG and wget.
    
    ```bash
    sudo apt update && sudo apt install gpg wget
    ```

    Download the keyring
    
    ```bash
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    ```

    Verify the keyring
    ```bash
    gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint
    ```

    Add the HashiCorp repository
    ```bash
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list
    ```

    Install Vault
    ```bash
    sudo apt update && sudo apt install vault
    ```

    Verify the installation
    ```bash
    vault --version
    ```


    **Configure Vault**

    Create directory path for vault
    ```bash
    mkdir -p /opt/vault/data
    ```
  
    Edit configuration file
    ```bash
    sudo nano /etc/vault.d/vault.hcl
    ```

    ```yaml
    ui = true
    api_addr = "http://0.0.0.0:8200"
    log_level = "INFO"

    storage "file" {
      path = "/opt/vault/data"
    }

    listener "tcp" {
      address = "0.0.0.0:8200"
      tls_disable = true
    }
    ```

    TLS disabled since we're just communicating with `build-machine`. Use TLS encryption for production environment.

    
    Enable vault service
    ```bash
    sudo systemctl enable vault
    sudo systemctl start vault
    ```
    
    Confirm vault service is running
    ```bash
    sudo systemctl status vault
    ```
    
    Set environment variable for vault address
    This will configure the Vault client to talk to the dev server.
    ```bash
    export VAULT_ADDR="http://192.168.149.8:8200"
    ```
    
    Generate Unseal keys and Root token
    ```bash
    vault operator init
    ```    

    Verify the server is running
    ```bash
    vault status
    ```

    Start Unseal process with Unseal Key 1
    
    ```bash
    vault operator unseal
    ```
    Implement this three times with other Unseal keys to increment Unseal progress by 1 until `Sealed` state is `false`.

    
    **Vault policy requirements**

     it is recommended that root tokens are only used for just enough initial setup or in emergencies.
    
     As a best practice, use tokens with appropriate set of policies based on your role in the organization.   

     **Write a Vault Policy**

     As an admin user, we must be able to:
     - Read system health check
     - Create and manage ACL policies broadly across Vault
     - Enable and manage authentication methods broadly across Vault
     - Manage the Key-Value secrets engine enabled at secret/ path

     Define the admin policy in the file named `admin-policy.hcl`
  
     ```bash  
     tee admin-policy.hcl <<EOF
     
     # Read system health check
     path "sys/health"
     {
       capabilities = ["read", "sudo"]
     }

     # Create and manage ACL policies broadly across Vault

     # List existing policies
     path "sys/policies/acl"
     {
       capabilities = ["list"]
     }

     # Create and manage ACL policies
     path "sys/policies/acl/*"
     {
       capabilities = ["create", "read", "update", "delete", "list", "sudo"]
     }

     # Enable and manage authentication methods broadly across Vault

     # Manage auth methods broadly across Vault
     path "auth/*"
     {
       capabilities = ["create", "read", "update", "delete", "list", "sudo"]
     }

     # Create, update, and delete auth methods
     path "sys/auth/*"
     {
       capabilities = ["create", "update", "delete", "sudo"]
     }

     # List auth methods
     path "sys/auth"
     {
       capabilities = ["read"]
     }

     # Enable and manage the key/value secrets engine at `secrets/` path

     # List, create, update, delete and patch key/value secrets
     path "secrets/*"
     {
       capabilities = ["create", "read", "update", "delete","patch", "list", "sudo"]
     }

     # Manage secrets engines
     path "sys/mounts/*"
     {
       capabilities = ["create", "read", "update", "delete", "list", "sudo"]
     }

     # List existing secrets engines.
     path "sys/mounts"
     {
       capabilities = ["read"]
     }
     EOF
     ```

     **Create admin policy**
     
     Create a policy named admin with the policy defined in admin-policy.hcl
     
     ```bash
     vault policy write admin admin-policy.hcl
     ```

     **Display New Policy**
   
     List all policies
     ```bash
     vault policy list
     ```
  
     Read the `admin` policy.
     Displays the paths and capabilities defined for this policy.
     ```bash
     vault policy read admin
     ```

     **Create new token**
     
     Create a token with the admin policy attached and store the token in the variable `ADMIN_TOKEN`

     ```bash
     ADMIN_TOKEN=$(vault token create -format=json -policy="admin" | jq -r ".auth.client_token")
     ```

     Display the `ADMIN_TOKEN`
     ```bash
     echo $ADMIN_TOKEN
     ```

     The admin policy defines capabilities for the paths.
     Retrieve the capabilities of this token for the `secrets/` path.
     ```bash
     vault token capabilities $ADMIN_TOKEN secrets/*
     ```

     Set the `VAULT_TOKEN` environment variable to interact with Vault.
     Setting this environment variable is a way to provide the token to Vault via CLI
     ```bash
     export VAULT_TOKEN="<ADMIN_TOKEN>"
     ```    
     
    Append environment variables to `.profile`
    
    Ensure they're automatically set up and available in every new shell session.
    
    Fill in your ADMIN_TOKEN
    ```bash
    cat << EOF | sudo tee -a ~/.profile
    export VAULT_ADDR="http://192.168.149.8:8200"
    export VAULT_TOKEN="<ADMIN_TOKEN>"
    
    EOF
    ```

    **Create KV secrets engine**
    
    Enable the key/value secrets engine v1 at secrets/.
    ```bash
    vault secrets enable -path="secrets" -description="Secret engine for Vsphere Connection" kv
    ```

    List enabled secrets engines
    ```bash
    vault secrets list 
    ```

    **Save multiple key-value pairs**
    
    Create a file named vsphere.json that defines `cluster`, `datacenter`, `esx_datastore`, `esx_host`, `server`, `username` and  `password` fields.
    
    ```bash
    tee vsphere.json <<EOF
    {
      "username": "administrator@vsphere.local",
      "password": "Lioness123@#"
      "server": "vcenter-II",
      "datacenter": "odennav-labs",
      "cluster": "odennav-labs-cluster",
      "esx_host": "ESXi-2",
      "esx_datastore": "datastore-2"
    }
    EOF
    ```

    **Create new secrets**
    
    Create a secret at path secrets/vmware with keys and values defined in vsphere.json.    
    ```bash
    vault kv put secrets/vmware @vsphere.json
    ```
    
    **Disable Vault command history**

    The option above ensures that the contents of the secret do not appear in the shell history. 
    The secret path would still be accessible through the shell history.

    We can configure our shell to avoid logging any `vault` commands to your history.

    In Bash profile, set the history to ignore all commands that start with `vault`.
    
    ```bash
    cat << EOF | sudo tee -a ~/.profile
    export HISTIGNORE="&:vault*"

    EOF
    ```

-----   
    
  **Web UI option to create Secrets engine**
   
  Access Vault Web UI at `http://192.168.149.8:8200/ui`
  Use Token method and input `Root token value` to login.
  
  - Enable secrets `new engine`, click the `KV` radio button and specify mount `Path`
  - Click `Enable Engine`
  - Click `Create secret` and set `Path` for this secret.
  - Enter key and value as `Secret Data`. You can add multiple key/value pairs.
  - Click `Save`

-----

*Please ensure vault remains unsealed until build project is completed*



4.  **PACKER INSTALLATION and CONFIGURATION**

    Packer is a modular tool built by Hashicorp to create raw VM images and templates.
    It's much more scalable than using a specific hypervisor tool.
    
    We'll be using Packer to create our VM images.

    **Packer Installation**   
   
     Add the HashiCorp GPG key.
     ```bash
     curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
     ```

     Add the official HashiCorp Linux repository
     ```bash
     sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
     ```

     Update and install
     ```bash
     sudo apt-get update && sudo apt-get install packer
     ```

     Verify installation
     ```bash
     packer --version
     ```
     
     **Image Build with Packer Template**
     
     With Packer installed, it is time to build our first image.
     
     A Packer template is a configuration file that defines the image you want to build and how to build it. 
     Packer templates use the Hashicorp Configuration Language (HCL).

     View the HCL block in `ubuntu20.pkr.hcl` template in `packer/ubuntu20` directory.
 
     ```yaml
     local "vcenter_username" {
         exprssion = vault(*/secrets/data/vmware", "username")
         sensitive = true
     }

     local "vcenter_password" {
         exprssion = vault(*/secrets/data/vmware", "password")
         sensitive = true
     }

     local "vcenter_server" {
         exprssion = vault(*/secrets/data/vmware", "server")
         sensitive = true
     }

     local "vcenter_datacenter" {
         exprssion = vault(*/secrets/data/vmware", "datacenter")
         sensitive = true
     }

     local "vcenter_cluster" {
         exprssion = vault(*/secrets/data/vmware", "vcenter_cluster")
         sensitive = true
     }

     local "esx_host" {
         exprssion = vault(*/secrets/data/vmware", "esx_host")
         sensitive = true
     }

     local "esx_datastore" {
         exprssion = vault(*/secrets/data/vmware", "esx_datastore")
         sensitive = true
     }

     locals {
         buildtime = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
     }

     source "vsphere-iso" "ubuntu20" {
         username = local.vcenter_username
         password = local.vcenter_password         
         vcenter_server = local.vcenter_server
         datacenter = local.vcenter_datacenter
         cluster = local.vcenter_cluster
         host = local.esx_host
         folder = "Templates"
         datastore = local.esx_datastore
         insecure_connection = "true"

 
         remove_cdrom = true
         convert_to_template = true
         guest_os_type = "ubuntu64Guest"
         notes = "Built by Packer on ${local.buildtime}"

         vm_name = "packer_ubuntu20"
         CPUs = "1"
         RAM = "8192"
         disk_controller_type = ["pvscsi"]
         firmware = "bios"

         storage {
             disk_size = "40960"
             disk_thin_provisioned = true
         }


         network_adapters {
             network = "VM Network"
             network_card = "vmxnet3"
         }

         iso_paths = [
             “[$(local.esx_datastore)] ubuntu-20.04.6-live-server-amd64”
         ]
         iso_checksum = “none”

         boot_order = "disk,cdrom"
         boot_wait = “5s” 
         boot_command = [
             "<esc><esc><esc>",
             "<enter><wait>",
             "/casper/vmlinuz ",
             "root=/dev/sr0 ",
             "initrd=/casper/initdrd ",
             "autoinstall ",
             "ds=nocloud-net;s=http://192.168.149.8:8600/",
             "<enter>
         ]
         ip_wait_timeout = "20m"
         ssh_password = "ubuntu"
         ssh_username = "ubuntu"
         ssh_timeout = "20m"
         ssh_handshake_attempts = "100"
         communicator = "ssh"

         shutdown_command = "sudo -S -E shutdown -P now"
         shutdown_timeout = "15m"

         http_port_min = 8600
         http_port_max = 8600
         http_directory = "./artifacts"
     }


     build {
         sources = ["source.vsphere-iso.ubuntu20"]

         provisioner "shell" {
             inline [
                 "echo Running updates",
                 "sudo apt-get update",
                 "sudo apt-get -y install open-vm-tools",
                 "sudo touch /etc/cloud/cloud-init.disabled", # Fixing issues with preboot DHCP
                 "sudo apt-get -y purge cloud-init",
                 "sudo sed -i \"s/D /tmp 1777/#D /tmp 1777/\" /usr/lib/tmpfiles.d/tmp.conf",
                 "sudo sed -i \"s/After=/After=dbus.service /\" /lib/systemd/system/open-vm-tools.service",
                 "sudo rm -rf /etc/machine-id", # next four lines fix same ip address being assigned in vmware
                 "sudo rm -rf /var/lib/dbus/machine-id",
                 "sudo touch /etc/machine-id",
                 "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id"
             ]    
         }     
     }     
     ```

     Note the cloud config boot file in `packer/ubuntu20/artifacts/user-data` 
     View autoinstall configuration in `user-data`

 
     Initialize your Packer configuration
     ```bash
     cd ~/on-prem-devops-vsphere/packer/ubuntu20/
     packer init ubuntu20.pkr.hcl
     ```
  
     Ensure template has consistent format
     ```bash
     packer fmt ubuntu20.pkr.hcl
     ```

     Ensure your configuration is syntactically valid and internally consistent 
     ```bash
     packer validate ubuntu20.pkr.hcl
     ```

     Build image
     ```bash
     packer build ubuntu20.pkr.hcl
     ```
      
     View `packer_ubuntu20` VM template created in vcenter vsphere web client.

-----
 
5. **TERRAFORM INSTALLATION and VM DEPLOYMENT**


   **Install Terraform**

   Ensure that your system is up to date and you have installed the gnupg, software-properties-common, and curl packages installed.
   
   We'll use these packages to verify HashiCorp's GPG signature and install HashiCorp's Debian package repository.
   ```bash
   sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
   ```

   Install the HashiCorp GPG key.
   ```bash
   wget -O- https://apt.releases.hashicorp.com/gpg | \
   gpg --dearmor | \
   sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
   ```
   
   Verify the key's fingerprint. The `gpg` command will report the key fingerprint.
   ```bash
   gpg --no-default-keyring \
   --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
   --fingerprint
   ```

   Add the official HashiCorp repository to your system. 
   ```bash
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
   https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
   sudo tee /etc/apt/sources.list.d/hashicorp.list
   ```

   Download the package information from HashiCorp.
   ```bash
   sudo apt update
   ```

   Install Terraform from the new repository.
   ```bash
   sudo apt-get install terraform
   ```

   Verify that the installation
   ```bash
   terraform version
   ```

 
   **Provision VM Instances on VMware vSphere**
   
   Initialize the configuration directory `on-prem-devops-vsphere/terraform/` and install the `vSphere` providers defined in the configuration.
   ```bash
   cd on-prem-devops-vsphere/terraform/
   terraform init
   ```

   Format your configuration
   ```bash
   terraform fmt
   ```

   Validate your configuration
   ```bash
   terraform validate
   ```

   Create an execution plan that describes the changes terraform will make to the infrastructure
   ```bash
   terraform plan
   ```

   Apply the configuration and provision the VMs
   ```bash
   terraform apply
   ```
 
   Note, the ansible inventory is built dynamically by terraform with resource `"local_file" "ansible_inventory"` shown below 
   
   
   Here is the .tpl terraform trmplate code for logical groupings


-----

6. **ANSIBLE INSTALLATION and MACHINE CONFIGURATION**
   
   **Install Ansible**
   
   Configure the PPA on your system and install Ansible
   ```bash
   sudo apt update
   sudo apt install software-properties-common
   sudo add-apt-repository --yes --update ppa:ansible/ansible
   sudo apt install ansible
   ```

   **Run ansible playbooks**
   
   Bootstrap each web server 
   Default user `ubuntu` used as `remote_user` in `on-prem-devops-vsphere/ansible/ansible.cfg` is not created yet
   ```bash
   ansible-playbook -u ubuntu add_user.yaml
   ```

   Remove Ubuntu default user from each web server
   ```bash
   ansible-playbook remove_ubuntu.yaml
   ```

   **Load-balanced application deployment with ansible**
   
   Deploy and configure a load-balancer and multiple servers on vSphere VMs in datacenter cluster.

   Install Nginx on vSphere Virtual Machines and configure as web servers
   ```bash
   ansible-playbook install_nginx_ws.yaml
   ```

   Install Nginx on vSphere Virtual Machine and configure as load balancer
   ```bash
   ansible-playbook install_nginx_lb.yaml
   ```

   **Verify web server and load balancer installation**

   ```bash
   curl <ws01 ipv4 address>:80
   curl <ws02 ipv4 address>:80
   curl <ws03 ipv4 address>:80
   ```

   ```bash
   curl <lb01 ipv4 address>:80
   ```

-----

##  Automated Pipeline

1.  **Jenkins Setup**

    Jenkins is a self-contained, open source automation server which can be used to automate all sorts of tasks related to building, testing, and delivering or deploying software.

    Our Jenkins Workflow:
    - Define when to run job
    - Download latest source code updates
    - Run specified set of commands
    - Create output artifacts(VM templates)
    - Save console output for future debugging & troubleshooting

    Generate ssh key-pair
    ```bash
    ssh-keygen -t rsa -b 4096 
    ```

    Create local jenkins directories for volume mapping
    ```bash
    sudo mkdir -p /opt/jenkins/bin
    sudo mkdir -p /opt/jenkins/jenkins-docker-certs
    ```
    
    Locate executable files of packer command
    ```bash
    which packer
    ```

    Locate executable files of terraform command
    ```bash
    which terraform
    ```

    Copy binaries to jenkins directory volume
    ```bash
    sudo cp -rf /usr/bin/packer /opt/jenkins/bin
    sudo cp -rf /usr/bin/terraform /opt/jenkins/bin
    ```
 
    Confirm jenkins user permissions
    ```bash
    sudo chown -R odennav:odennav /opt/jenkins
    ```

    Run jenkins container
    ```bash
    sudo docker run \
      -d --name jenkins \
      --restart always \
      -v /opt/jenkins/jenkins-docker-certs:/certs/client \
      -v /opt/jenkins:/var/jenkins_home \
      -p 8080:8080 \
      -p 5000:5000 \
      -p 8600:8600 \
      jenkins/jenkins:lts-jdk17 
    ```

2.  **Unlock Jenkins**
    
    When you first access a new Jenkins instance, you are asked to unlock it using an automatically-generated password.

    Browse to http://<build-machine ip add>:8080 and wait until the Unlock Jenkins page appears.
    
    Discover `Administrator password` to unlock jenkins
    Copy and paste password into setup wizard
    ```bash
    sudo cat /opt/jenkins/secrets/initialAdminPassword 
    ```

   
    After unlocking jenkins, click one of the options: `Install suggested plugins` to install the recommended set of plugins based on most common use cases.
    
3.  **Create the First Administrator User**
    
    Finally, after customizing Jenkins with plugins, Jenkins asks you to create your first administrator user.
    Specify details for your administrator user, then save and continue setup.
 
    When the `Jenkins is ready` page appears, click `Start using Jenkins`
    
    Notes:
    - This page may indicate Jenkins is almost ready! instead and if so, click Restart.
    - If the page does not automatically refresh after a minute, use your web browser to refresh the page manually.


4.  **Add Gogs Plugin to Jenkins**
    
    We'll need to extend jenkins functionality with Gogs plugin.
    
    - At Jenkins Dashboard appears, Go to **Manage Jenkins** > **Manage Plugins**
    - Select **Available** tab and search for `gogs`
    - Select box button of available gogs plugin
    - Click on `Download now and install after restart` and select box button `Restart jenkins when installation is complete and no jobs are running`
    - Wait while jenkins restarts.
    
    
5.  **Configure Credentials**
    
    Next step is to create vault credentials in Jenkins.
    
    Login to Jenkins UI
    Go to **Manage Jenkins** > **Manage Credentials**
    
    Select `Jenkins` store
    Under **System** tab, select `Global credentials(unrestricted)`
    
    Check left tab and click on `Add Credentials`, then choose the following:
    - Kind: *secret text*
    - Secret: 
    - ID: *vault_token*
    
    Get your ADMIN_TOKEN to fill in `Secret` field
    ```bash
    echo $ADMIN_TOKEN
    ```

    
6.  **Create SSH Credentials in Jenkins**
    
    Go to **Manage Jenkins** > **Manage Credentials**
    
    Select `Jenkins` store
    Under **System** tab, select `Global credentials(unrestricted)`
    
    Check left tab and click on `Add Credentials`, then choose the following:
    - Kind: *SSH Username with private key*
    - ID: *id_rsa*
    - Username: *odennav*

    Under `Private Key`, select `Enter directly` radio button
    Copy your private key from here:
    ```bash
    cat ~/on-prem-devops-vsphere/keys/id_rsa
    ```
    Then paste in `Key` field and click `OK`
    
   
    
7.  **Add SSH Key to Gogs**
    
    We'll add our public key to Gogs to ensure ssh authentication with Jenkins.

    Go to gogs settings page at `http://192.168.149.8:3880/user/settings`  
    
    Select `SSH Keys` tab and click on `Add Key` on `Manage SSH Keys` tab
    
    Enter `Key Name` as `id_rsa`

    ```bash
    cat ~/on-prem-devops-vsphere/keys/id_rsa.pub | tr -d '\n'
    ```
    Copy your public key, paste into `Content` field and click `Add Key`



8.  **Automate CI/CD Pipeline**
 
    Go to Jenkins Dashboard and select `New Item` on left tab.

    Enter an item name, select `Freestyle project` and click `OK`
    
    When `General` setup page appears, scroll down to `Source Code Management` under `Gogs Webhook` tab and select radio button for `Git`
    
    Fill the `Repository URL` field with:
    ```bash
    ssh://git@192.168.149.8:2222/odennav/on-prem-devops-vsphere.git
    ```
    Select 'odennav' credentials for SSH keys
     
    Scroll down to `Build Environment` section under the `Build Triggers` tab
    
    Select box button `Use secret text(s) or file(s)`
    
    Add Binding for `Secret text`, enter variable name as `vault_token` and select credentials previously created `vault_token`


    Sroll down to `Build Environment` section under the `Build Environment` tab
    
    Click on `Add build step` drop down and select `Execute shell`
    
    Fill in the following into `Command` field:
    
    ```bash
    export VAULT_ADDR=http://192.168.149.8:8200"
    export VAULT_TOKEN=$vault_token
    export PACKER_LOG=1
    cd "./packer/"
    /var/jenkins_home/bin/packer init ubuntu20.pkr.hcl
    /var/jenkins_home/bin/packer build -force ubuntu20.pkr.hcl
    export TF_LOG=INFO
    cd "./packer/terraform"
    /var/jenkins_home/bin/terraform init
    /var/jenkins_home/bin/terraform validate
    /var/jenkins_home/bin/terraform plan
    /var/jenkins_home/bin/terraform apply -auto-approve
    cd "./packer/ansible"
    /var/jenkins_home/bin/ansible ansible-playbook -u ubuntu add_user.yaml
    /var/jenkins_home/bin/ansible ansible-playbook remove_ubuntu.yaml
    /var/jenkins_home/bin/ansible ansible-playbook install_nginx_ws.yaml
    /var/jenkins_home/bin/ansible ansible-playbook install_nginx_lb.yaml
    ```
    Click `Save`

    The Jenkins dashboard will show your project build just created.
    
    Select `Build Now` at left tab and the build job will show up under `Build History` section
    
    Click on this job, select 'Console Output` at left tab and view the build job in real time.


    When build job is completed, check the vSphere datacenter and confirm the following are deployed:
    - VM template 
    - web01
    - web02
    - web03
    - lb01

   **Browse website deployed on web servers through load balancer**

   View the Level website on your browser.

   ![](https://github.com/odennav/on-prem-devops-vsphere/blob/main/docs/2095-level.jpg)

-----
Enjoy!
   
    
