# Project 3 — AWS CI/CD Web App (GitHub → CodePipeline → CodeBuild → CodeDeploy → EC2 ASG behind ALB)

## Summary
This project implements an end-to-end CI/CD pipeline on AWS. A simple static web page (`index.html`) is stored in GitHub. Every push triggers an automated pipeline that builds an artifact and deploys it to an Auto Scaling Group (private subnets) running Nginx. The application is served through an Application Load Balancer (public subnet).

Compared to Projects 1 and 2, Project 3 took significantly longer because it introduced many new, real-world deployment concepts (CodeDeploy lifecycle, AppSpec rules, agent troubleshooting, Linux package edge cases on Amazon Linux 2023, and ASG-safe idempotent scripts). A large portion of the work was debugging failures during deployment and making the deployment process stable for newly launched instances.

---

## What I Built

### End-to-end CI/CD
- **Source**: GitHub repository
- **Pipeline Orchestration**: AWS CodePipeline
- **Build Stage**: AWS CodeBuild
- **Deploy Stage**: AWS CodeDeploy (EC2/On-Premises deployment type)
- **Target**: EC2 instances managed by an **Auto Scaling Group**
- **Web Server**: Nginx on Amazon Linux 2023
- **Ingress**: Application Load Balancer (ALB)

### Key Outcome
After the pipeline succeeds, browsing the **ALB DNS** shows:

> `Version 1 - Deployed via CodeDeploy`

---

## Architecture (High-level)

Internet  
→ **ALB (Public Subnet)**  
→ Target Group  
→ **Auto Scaling Group (Private Subnets)**  
→ EC2 instances running Nginx (serving `/usr/share/nginx/html/index.html`)  

Operational access (debugging / SSH):  
→ **Bastion Host (Public Subnet)**  
→ Private EC2 instances

---

## AWS Services & Concepts Learned

### 1) CodePipeline
- Orchestrates the entire flow: Source → Build → Deploy
- Automatically triggers on GitHub changes
- Shows a clear execution graph and stage-by-stage status

### 2) CodeBuild
- Runs build steps defined in `buildspec.yml`
- Packages the repository contents as an artifact for CodeDeploy
- Key learning: build stage may succeed even if deploy fails (so debugging is often in CodeDeploy logs)

### 3) CodeDeploy
- Deploys the artifact onto EC2 instances.
- Reads deployment instructions from `appspec.yml`.
- Runs lifecycle hooks (e.g., `AfterInstall`, `ApplicationStart`) that call shell scripts.
- **CodeDeploy Agent** on the EC2 instance is essential; it polls CodeDeploy and executes lifecycle events.

### 4) IAM Role vs Key Injection
- Instead of placing AWS keys inside EC2 (high leakage risk), I used **IAM Roles**:
  - **EC2 Instance Profile** lets EC2 call AWS services securely without static credentials.
- This is a core “cloud-native security” concept.

### 5) Idempotency (Critical for Auto Scaling)
- In an ASG, new instances can appear at any time.
- Deployment scripts must be **idempotent**:
  - Running them multiple times should not break the instance.
  - They should “converge” the system into the desired state.

This project taught me that CI/CD in a scaling environment is mostly about making automation reliable under repeated execution and variable instance states.

---

## Repository Structure

.
├── index.html
├── appspec.yml
├── buildspec.yml
└── scripts/
    ├── install.sh
    └── restart.sh


---

## How Deployment Works

### appspec.yml (What CodeDeploy Reads)
- Defines which files to copy and where to place them on the EC2 instance
- Defines lifecycle hooks and which scripts to run

Example design intent:
- Copy `index.html` → `/usr/share/nginx/html/index.html`
- AfterInstall → install/repair Nginx and required config files
- ApplicationStart → restart services if needed

### scripts/install.sh (AfterInstall)
- Installs Nginx and dependencies
- Creates missing config files (ex: `mime.types`) if required
- Ensures web root exists
- Validates config with `nginx -t`
- Restarts Nginx

### scripts/restart.sh (ApplicationStart)
- Restarts/validates Nginx
- Ensures the service is active

---

## Major Troubleshooting & Lessons Learned (Detailed)

This is the part that made Project 3 much harder than Projects 1–2.

### Issue A — “CodeDeploy agent was not able to receive the lifecycle event”
**Symptoms**
- Deployment failed with messages like:
  - “CodeDeploy agent was not able to receive the lifecycle event”
  - Too many instances failed deployment

**Diagnosis**
- Checked CodeDeploy agent status and logs on the instance
- Verified network connectivity to CodeDeploy endpoints

**Fix**
- Ensured the CodeDeploy Agent was installed and running.
- Ensured the instance IAM role and network access were sufficient.

**Lesson**
- CodeDeploy is not “push-only”; the agent must be healthy and able to poll AWS endpoints.

---

### Issue B — AppSpec “files section” error (source-only)
**Symptoms**
- Error: AppSpec file specifies only a source file; add destination

**Diagnosis**
- CodeDeploy requires explicit file mapping:
  - `source` and `destination` are both required

**Fix**
- Updated `appspec.yml` to include correct destination path

**Lesson**
- AppSpec syntax is strict, and small YAML mistakes can stop the entire deployment.

---

### Issue C — Nginx not installed / install hook not taking effect
**Symptoms**
- `nginx` command not found
- `systemctl status nginx` shows unit not found

**Diagnosis**
- Confirmed that the `AfterInstall` hook did not run successfully.
- Verified hook logs and script permissions.

**Fix**
- Ensured `install.sh` is executed by CodeDeploy under root.
- Ensured script is executable and uses correct shebang.

**Lesson**
- A successful pipeline “Build” does not guarantee “Deploy”; hook scripts are the real deployment.

---

### Issue D — RPM install failure: “Error unpacking rpm package nginx …”
**Symptoms**
- `dnf install nginx` failed with unpack errors

**Root Cause (Real-world edge case)**
A path conflict existed:
- Nginx package expects `/usr/share/nginx/html/index.html` to be a **file**
- But on some instances it existed as a **directory** due to previous experiments / incorrect deployments

This caused RPM extraction to fail because a file could not overwrite an existing directory.

**Fix**
- Made the script idempotent and defensive:
  - If `index.html` exists as a directory → remove it before installing nginx

**Lesson**
- Package managers assume filesystem invariants.
- Idempotent scripts must repair invalid states before proceeding.

---

### Issue E — Nginx fails to start: missing `/etc/nginx/mime.types`
**Symptoms**
- `nginx -t` failed:
  - `open() "/etc/nginx/mime.types" failed`
- `systemctl start nginx` failed

**Root Cause**
On Amazon Linux 2023, the packaging/environment may result in cases where:
- `nginx.conf` exists and includes `mime.types`
- but `mime.types` file is missing on some instances

**Fix**
- Added logic to create a minimal `/etc/nginx/mime.types` if missing.
- Verified with `nginx -t` before starting the service.

**Lesson**
- Production automation must handle missing configuration dependencies.
- Always validate configs (`nginx -t`) before restarting services.

---

### Issue F — Instances in ASG had different states
**Symptoms**
- Some instances worked; others failed with different errors.

**Root Cause**
Auto Scaling Group launches instances over time; each instance may differ due to:
- partial previous deployments
- cached artifacts
- temporary failures
- filesystem differences

**Fix**
- “Convergent” install script:
  - installs required packages
  - creates missing directories
  - repairs known bad states
  - validates config
  - restarts service reliably
    
```bash
#idempotent code
dnf install nginx nginx-core nginx-filesystem
mkdir -p /usr/share/nginx/html
mkdir -p /etc/nginx
```


**Lesson**
- ASG environments require “self-healing” automation.
- Manual, instance-specific fixes do not scale—scripts must fix issues automatically.

---

## Verification Checklist

On an instance:
```bash
sudo nginx -t
sudo systemctl status nginx --no-pager -l
curl localhost
