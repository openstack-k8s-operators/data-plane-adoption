# Barbican Proteccio Adoption Role

Ansible role for adopting Barbican service from OpenStack 17.1 to RHOSO 18 with Proteccio HSM integration.

## 🔗 **Relationship to Existing Barbican Adoption Role**

This repository contains **two distinct Barbican adoption roles**:

### 1. `barbican_adoption` (Standard)
- **Purpose**: Standard Barbican adoption without HSM
- **Backend**: Uses `simple_crypto` plugin only
- **Use Case**: Standard OpenStack deployments
- **Process**: Simple configuration adoption and service deployment

### 2. `barbican_proteccio_adoption` (HSM-Enabled) - **This Role**
- **Purpose**: Barbican adoption with Proteccio HSM integration
- **Backend**: Supports both `simple_crypto` and `pkcs11` (HSM) plugins
- **Use Case**: High-security environments requiring HSM
- **Process**: Complex multi-phase adoption with HSM configuration

**WARNING: Important**: These roles are **mutually exclusive**. Choose the appropriate role based on your source environment:
- If your TripleO 17.1 has **standard Barbican** → use `barbican_adoption`
- If your TripleO 17.1 has **Proteccio HSM integration** → use `barbican_proteccio_adoption`

## WARNING: **IMPORTANT: Customization Required**

**This role contains placeholder values that MUST be customized for your environment before use.**

### Required Customization Steps:

1. **Copy and customize the sample variables:**
   ```bash
   cp vars/sample_environment.yml vars/my_environment.yml
   # Edit vars/my_environment.yml with your values
   ```

2. **Generate your own KEK key:**
   ```bash
   openssl rand -base64 32
   ```

3. **Update the following in `vars/my_environment.yml`:**
   - `source_undercloud_host`: Your actual undercloud hostname
   - `source_controller_host`: Your actual controller hostname
   - `barbican_simple_crypto_kek`: Your generated 32-byte base64 key
   - `hsm_login_password`: Your HSM login password
   - `hsm_token_labels`: Your HSM token label
   - `proteccio_required_files`: List your actual certificate filenames
   - `work_dir` and `proteccio_files_dir`: Your actual directory paths

4. **Use your custom variables:**
   ```bash
   ansible-playbook -i inventory.proteccio.yaml -e @vars/my_environment.yml playbooks/barbican_proteccio_adoption.yml
   ```

## Key Features

- **Automatic RabbitMQ user management** to prevent service authentication failures
- **Graceful HSM role dependency handling** with fallback mechanisms
- **Database adoption with backup and verification** capabilities
- **Custom Proteccio image deployment** and HSM configuration management
- **Comprehensive relationship with standard adoption** - clearly separated workflows

## Documentation

For complete documentation, see the official adoption guide:

- **Procedure**: `docs_user/modules/proc_adopting-key-manager-service-with-proteccio-hsm.adoc`
- **Concept**: `docs_user/modules/con_key-manager-service-adoption-approaches.adoc`
- **Troubleshooting**: `docs_user/modules/ref_troubleshooting-key-manager-proteccio-adoption.adoc`

## Quick Start

**WARNING: DO NOT run without customization - it will fail with placeholder values!**

### **Recommended Approach: Use the Adoption Script**

```bash
# 1. Navigate to the tests directory
cd /path/to/your/dp-adopt/tests

# 2. Configure script environment
cp config.env.sample config.env
vim config.env  # Update paths for your environment

# 3. Customize role variables
cp roles/barbican_proteccio_adoption/vars/sample_environment.yml \
   roles/barbican_proteccio_adoption/vars/my_environment.yml
vim roles/barbican_proteccio_adoption/vars/my_environment.yml  # Update with your values

# 4. Execute the adoption
./run_proteccio_adoption.sh
```

### **Alternative: Direct Ansible Execution (Advanced Users)**

```bash
# For advanced users or troubleshooting specific phases
ansible-playbook -i inventory.proteccio.yaml \
  -e @roles/barbican_proteccio_adoption/vars/my_environment.yml \
  playbooks/barbican_proteccio_adoption.yml
```

## Dependencies

### **MANDATORY Requirements**

- **`ansible-role-rhoso-proteccio-hsm` role**: **REQUIRED** - This role is absolutely mandatory for Proteccio HSM adoption. It MUST be executed either:
  - As part of this adoption process (automatic execution), OR
  - Before running this adoption process (manual execution)
  - **WITHOUT THIS ROLE, THE ADOPTION WILL FAIL**

- **Proteccio client files**: All certificate and key files must be present in the specified directory
- **OpenStack 17.1 source environment** with **Proteccio HSM integration** already configured
- **RHOSO 18 target cluster** with administrative access
- **Kubernetes/OpenShift CLI access** with appropriate permissions

### **Critical HSM Role Information**

The `ansible-role-rhoso-proteccio-hsm` role is responsible for:
- Creating essential Kubernetes secrets (`hsm-login`, `proteccio-data`)
- Mounting Proteccio certificate files in the target environment
- Configuring HSM authentication for Barbican services

**This role is NOT optional**. If you attempt to run the adoption without it:
- The adoption process will fail with clear error messages
- Barbican services will not be able to access the HSM
- Your existing HSM-protected secrets will become inaccessible

## Troubleshooting

If Barbican services show CrashLoopBackOff after deployment, the role automatically:
1. Extracts RabbitMQ credentials from transport URLs
2. Creates missing RabbitMQ users
3. Sets appropriate permissions
4. The services should recover automatically

## Security Note

**Never commit files containing real credentials, passwords, or certificate data to version control.**
