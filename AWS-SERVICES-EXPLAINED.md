# AWS Services Explained (Beginner Notes)

This document saves clear, beginner-friendly explanations of important AWS services that appear in this Terraform project and in [README_PLAN.md](README_PLAN.md).

These explanations were created during learning sessions so you can review them anytime.

---

## Table of Contents

- [What is WAF?](#1-what-is-waf)
- [Route 53](#2-route-53)
- [ACM - AWS Certificate Manager](#3-acm---aws-certificate-manager)
- [Secrets Manager](#4-secrets-manager)
- [How These Services Work Together](#5-how-these-services-work-together)

---

## 1. What is WAF?

**WAF** stands for **Web Application Firewall**.

### Simple Explanation

Imagine your application is a house:

- **Security Groups** = The security guard at the front gate.  
  They check: *"Is this person allowed to come in on port 80 or 443?"*  
  They work at the **network level** (IP addresses + ports).

- **WAF** = A smarter security guard **inside** the house, standing right in front of your living room.  
  They look at what the person is **actually saying or doing**, not just which door they came through.

WAF inspects the **HTTP/HTTPS traffic** (the actual web requests) and decides whether to allow, block, or challenge the request based on rules.

### Why Security Groups Are Not Enough

| Feature                    | Security Group       | WAF                              |
|---------------------------|----------------------|----------------------------------|
| Block by IP/Port          | Yes                  | Yes                              |
| Block malicious patterns  | No                   | Yes                              |
| Block SQL Injection       | No                   | Yes                              |
| Block XSS attacks         | No                   | Yes                              |
| Rate limiting (stop bots) | Very limited         | Yes (very good at this)          |
| Block bad bots            | No                   | Yes                              |
| Protect against OWASP Top 10 | No                | Yes                              |

A hacker can send a perfectly valid request on port 80 (which your Security Group allows), but the **content** of that request can be dangerous.

### What Can AWS WAF Protect Against?

- SQL Injection (`' OR 1=1 --`)
- Cross-Site Scripting (XSS)
- Bad bots and scrapers
- Brute force attacks
- Requests from known malicious IP addresses
- Too many requests in a short time (rate limiting)

### How WAF Fits in This Project

According to [README_PLAN.md](README_PLAN.md), the target traffic flow should be:

```
User
  ↓
Route 53
  ↓
AWS WAF               ← Protection layer
  ↓
Application Load Balancer (ALB)
  ↓
ECS Fargate Tasks
```

WAF sits **in front of the ALB**. Every request must pass through WAF rules before reaching your load balancer.

**Current Status:** Not implemented yet. The plan suggests creating `modules/waf`.

---

## 2. Route 53

**Route 53** is AWS’s **DNS (Domain Name System)** service.

### Simple Explanation

Route 53 translates human-friendly domain names into technical addresses.

**Analogy:**  
It works like a phone book or contact list:
- You type `myapp.example.com`
- Route 53 tells the internet: *"This name belongs to the ALB at this address"*

### Why You Need It in This Project

Currently, your application can only be reached using the long, ugly ALB DNS name:

```
my-app-alb-123456789.ap-southeast-1.elb.amazonaws.com
```

With Route 53, you can use a clean custom domain:

```
https://app.mycompany.com
```

### Role in the Architecture

Route 53 is the **first entry point** for users who want to use a real domain name.

**Key Terraform resources:**
- `aws_route53_record` (Alias record pointing to the ALB)
- `data "aws_route53_zone"` (to reference an existing domain)

**Important Note from the Plan:**
Before creating a Route 53 alias record, the ALB module must output `alb_zone_id` (currently it only outputs `alb_dns_name`).

---

## 3. ACM - AWS Certificate Manager

**ACM** (AWS Certificate Manager) provides **free SSL/TLS certificates** so your site can use `https://`.

### Simple Explanation

- HTTP = Sending information like a **postcard** (anyone can read it)
- HTTPS = Sending information in a **locked envelope**
- ACM = The free service that gives you the lock and key

### Why You Need It

Your current ALB only has an HTTP listener on port 80. This is not secure for real applications.

With ACM you can:
- Add an HTTPS listener on port 443
- Automatically redirect HTTP traffic to HTTPS
- Get a trusted certificate that browsers accept

### How ACM Works with Route 53

This is a very common and important combination:

1. You request a certificate in ACM for `app.example.com`
2. ACM needs to verify that **you own the domain**
3. The easiest method is **DNS validation**
4. ACM asks you to create a special DNS record in **Route 53**
5. Once validated, ACM issues the certificate automatically

### Role in the Project Plan

The plan recommends this order:
1. Create `modules/acm`
2. Update the ALB module to support HTTPS + HTTP-to-HTTPS redirect
3. Then add Route 53

---

## 4. Secrets Manager

**Secrets Manager** is a secure service for storing sensitive information (passwords, API keys, database credentials, tokens, etc.).

### Simple Explanation

Instead of writing passwords in your code, Terraform files, or environment variables, you store them in a highly secure digital vault.

Your application can request the secret when it needs it — without ever exposing it.

### Why This Is Important

Currently, if your ECS application needs a database password or third-party API key, there is no secure way to provide it.

Secrets Manager solves this by:
- Encrypting secrets at rest
- Providing temporary access to applications
- Supporting automatic secret rotation (advanced)
- Keeping secrets out of Terraform state and source code

### How It Connects to ECS

In the ECS Task Definition, you can reference secrets like this:

```hcl
secrets = [
  {
    name      = "DATABASE_PASSWORD"
    valueFrom = "arn:aws:secretsmanager:ap-southeast-1:123456789:secret:my-db-password"
  }
]
```

The IAM role created in `modules/iam` will also need permission to read these secrets.

**Current Status:** Not implemented. The plan places this in **Step 6** (`modules/secrets`).

---

## 5. How These Services Work Together

Here is the recommended production flow according to the project plan:

```
User
  ↓
Route 53 (custom domain)
  ↓
AWS WAF (security protection)
  ↓
ALB with HTTPS (using ACM certificate)
  ↓
ECS Fargate Tasks
  ↓
Container reads secrets securely from Secrets Manager
```

### Recommended Learning & Implementation Order

| Order | Service            | Why This Order?                              |
|-------|--------------------|----------------------------------------------|
| 1     | ACM                | Needs Route 53 for easy validation           |
| 2     | Route 53           | Needs ACM certificate for HTTPS              |
| 3     | WAF                | Best placed in front of HTTPS ALB            |
| 4     | Secrets Manager    | Can be added independently when needed       |

---

## Summary Table

| Service            | Main Purpose                          | Current Status in Project | Needed For                  | Beginner Difficulty |
|--------------------|---------------------------------------|---------------------------|-----------------------------|---------------------|
| **WAF**            | Protect web apps from attacks         | Not implemented           | Security                    | Medium              |
| **Route 53**       | Custom domain names                   | Not implemented           | Professional URLs           | Medium              |
| **ACM**            | Free HTTPS certificates               | Not implemented           | Secure traffic (`https://`) | Medium              |
| **Secrets Manager**| Securely store passwords & keys       | Not implemented           | Security & best practices   | Easy to Medium      |

---

**Tip for Future Review:**

Whenever you work on the following steps from [README_PLAN.md](README_PLAN.md), come back and re-read the relevant sections:

- Step 3 → ACM
- Step 4 → Route 53
- Step 5 → WAF
- Step 6 → Secrets Manager

This document was created to help you review these concepts without searching through chat history.