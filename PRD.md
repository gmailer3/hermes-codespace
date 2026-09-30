# PRD — Hermes Agent on GitHub Codespaces

**Version:** 1.0  
**Date:** September 28, 2026  
**Status:** Proposed  
**Platform:** GitHub Codespaces  
**Agent:** NousResearch Hermes Agent

## 1. Overview

Build a GitHub Codespaces-based environment that allows the Hermes Agent to operate as an autonomous AI agent with access to:

- A Linux development environment
- Browser automation
- Configurable AI models/APIs
- Persistent configuration and workspace files
- Client-provided information uploaded through a controlled interface
- Authorized website interaction
- Logging and execution status
- Optional remote communication/control

The system should be designed so that the Codespace can be recreated reliably while keeping configuration, credentials, and project data separated from source code.

## 2. Primary Objective

The primary objective is to create a reliable environment where Hermes can:

1. Start inside a GitHub Codespace.
2. Load its configuration automatically.
3. Connect to the selected AI model/API.
4. Access a browser automation environment.
5. Read structured client information supplied by the user.
6. Navigate an authorized website.
7. Perform the authorized workflow using the supplied information.
8. Report successful completion or errors.
9. Preserve useful logs and state between sessions where supported.

## 3. Target Architecture

```text
                    ┌──────────────────────┐
                    │     GitHub Repo      │
                    │                      │
                    │  Configuration       │
                    │  Scripts             │
                    │  Dockerfile          │
                    │  Documentation       │
                    └──────────┬───────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   GitHub Codespace   │
                    │                      │
                    │ Linux                 │
                    │ Python/Node.js        │
                    │ Hermes Agent         │
                    │ Browser              │
                    └──────────┬───────────┘
                               │
                 ┌─────────────┼─────────────┐
                 ▼             ▼             ▼
          ┌───────────┐ ┌────────────┐ ┌───────────┐
          │ AI Model  │ │ Browser    │ │ Workspace │
          │ API       │ │ Automation │ │ Data      │
          └───────────┘ └─────┬──────┘ └───────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │ Authorized      │
                     │ Website         │
                     └─────────────────┘
```

## 4. Functional Requirements

### FR-1: Codespace Environment

The project must provide a reproducible Codespaces environment.

Required components:

- Linux-based Codespace
- Python
- Node.js where required
- Git
- Hermes Agent
- Browser automation dependencies
- Chromium/Chrome-compatible browser
- Required browser drivers/tools
- Basic networking utilities

The environment should be defined through:

```text
.devcontainer/
├── devcontainer.json
├── Dockerfile
└── scripts/
```

The Codespace should automatically install or initialize required dependencies.

## 5. Hermes Installation

Hermes should be installed automatically when creating a new Codespace.

The setup process should:

1. Detect the operating system.
2. Install required system packages.
3. Install Hermes.
4. Install Python dependencies.
5. Install browser dependencies.
6. Validate the Hermes installation.
7. Validate browser availability.
8. Display a setup summary.

Example validation:

```text
[OK] Python
[OK] Node.js
[OK] Hermes
[OK] Browser
[OK] Browser automation
[OK] Environment configuration
```

If a dependency fails, setup must stop with a clear error.

## 6. Configuration Management

Sensitive information must NOT be hard-coded into the repository.

### Public configuration

Example:

```text
HERMES_MODEL=
BROWSER_MODE=
WORK_DIR=
LOG_LEVEL=
TARGET_URL=
```

### Secret configuration

Examples:

```text
AI_API_KEY
GITHUB_TOKEN
TELEGRAM_BOT_TOKEN
WEBSITE_CREDENTIALS
OTHER_PRIVATE_KEYS
```

Secrets should be provided through:

- GitHub Codespaces Secrets
- Environment variables
- GitHub repository/environment secrets where appropriate

Secrets must never be committed to Git.

## 7. AI Model Configuration

The system should support configurable AI providers rather than permanently locking Hermes to one model.

Example:

```text
MODEL_PROVIDER=google
MODEL_NAME=gemini-3-flash-preview
```

The architecture should allow future providers such as:

- Google
- OpenAI
- Anthropic
- NVIDIA NIM
- OpenRouter
- GLM-compatible APIs
- Other OpenAI-compatible endpoints

A configuration file should determine the active provider.

## 8. Browser Automation

Hermes must have access to a browser capable of interacting with authorized websites.

The browser environment should support:

- Page navigation
- Clicking
- Text entry
- Form interaction
- File uploads
- Reading page content
- Taking screenshots
- Detecting page changes
- Handling normal browser dialogs
- Maintaining a browser session when required

Browser automation must operate only against websites and workflows the operator is authorized to use.

## 9. Client Information Input

The system should provide a structured way to supply client information to Hermes.

Recommended format:

```text
client_data/
├── client_001.json
├── client_002.json
└── client_003.json
```

Example:

```json
{
  "client_id": "client_001",
  "first_name": "",
  "last_name": "",
  "email": "",
  "phone": "",
  "address": "",
  "username": "",
  "additional_information": {}
}
```

Sensitive client information should be handled securely and should not be written to public Git repositories.

## 10. Client Workflow

The intended workflow is:

```text
Client Information
        │
        ▼
Upload / Submit Data
        │
        ▼
Validate Data
        │
        ▼
Create Task
        │
        ▼
Hermes Reads Task
        │
        ▼
Launch Browser
        │
        ▼
Navigate to Authorized Website
        │
        ▼
Complete Authorized Workflow
        │
        ▼
Validate Result
        │
        ▼
Generate Execution Report
```

## 11. CAPTCHA / Anti-Bot Handling

The system must not attempt to bypass CAPTCHA, anti-bot protections, rate limits, access controls, or similar security mechanisms.

If a CAPTCHA or equivalent challenge appears, Hermes should:

1. Detect the challenge.
2. Pause the workflow.
3. Record the event.
4. Request authorized human interaction if appropriate.
5. Continue only after the challenge has been legitimately completed.

Example:

```text
CAPTCHA detected.

Automation paused.

Human action required.
```

## 12. Task Execution

Hermes should receive tasks in a structured format.

Example:

```json
{
  "task_id": "task_001",
  "client_id": "client_001",
  "target": "authorized-website",
  "operation": "client_onboarding",
  "input_file": "client_001.json"
}
```

Hermes should process one task at a time unless parallel execution is explicitly enabled.

## 13. Task State

Every task should have a state.

Possible states:

```text
QUEUED
STARTING
RUNNING
WAITING_FOR_USER
COMPLETED
FAILED
CANCELLED
```

Example:

```text
Task: client_001
Status: RUNNING
Started: 00:15
Browser: Connected
Hermes: Active
```

## 14. Logging

Every execution should generate structured logs.

Example:

```text
logs/
├── task_001.log
├── task_002.log
└── errors.log
```

Logs should record:

- Task ID
- Start time
- End time
- Major actions
- Errors
- Browser failures
- API failures
- Human-intervention requests
- Final status

Sensitive information should be redacted from logs.

## 15. Screenshots

Screenshots should be captured when useful for debugging.

Recommended events:

- Browser startup
- Major workflow failure
- Unexpected page
- CAPTCHA detection
- Final workflow state

Screenshots containing client information should be treated as sensitive data.

## 16. Error Handling

Hermes must distinguish between recoverable and non-recoverable errors.

### Recoverable

Examples:

- Temporary network failure
- Browser page timeout
- Temporary API failure
- Page reload failure

The system may retry with controlled limits.

### Non-recoverable

Examples:

- Invalid credentials
- Unauthorized website
- Missing required client information
- Persistent browser failure
- Website workflow changed
- CAPTCHA requiring human action

The task should stop and report the reason.

## 17. Retry Policy

Retries should be limited.

Example:

```text
Maximum retries: 3
Retry delay: exponential
Maximum retry delay: 60 seconds
```

The system must not continuously retry failed actions.

## 18. Security Requirements

The system must:

- Keep secrets outside Git.
- Avoid logging passwords/API keys.
- Restrict access to client files.
- Validate uploaded files.
- Use HTTPS whenever supported.
- Avoid storing unnecessary personal information.
- Provide a method to delete completed client data.
- Prevent accidental exposure of credentials through screenshots/logs.

## 19. Repository Structure

Recommended repository:

```text
hermes-codespace/
│
├── .devcontainer/
│   ├── devcontainer.json
│   ├── Dockerfile
│   └── setup.sh
│
├── config/
│   ├── config.example.env
│   └── models.yaml
│
├── client_data/
│   └── .gitkeep
│
├── tasks/
│   └── .gitkeep
│
├── logs/
│   └── .gitkeep
│
├── screenshots/
│   └── .gitkeep
│
├── scripts/
│   ├── start-hermes.sh
│   ├── health-check.sh
│   └── cleanup.sh
│
├── src/
│   ├── task_manager/
│   ├── browser/
│   ├── configuration/
│   └── logging/
│
├── .gitignore
├── README.md
└── PRD.md
```

## 20. Startup Process

When the Codespace starts:

```text
1. Initialize environment
2. Load environment variables
3. Validate required secrets
4. Validate Hermes
5. Validate browser
6. Validate API connection
7. Start task manager
8. Start Hermes
9. Display system status
```

Expected output:

```text
================================
 Hermes Codespace
================================

Hermes:       READY
Browser:      READY
AI Provider:  CONNECTED
Workspace:    READY
Task Manager: READY

Waiting for tasks...
```

## 21. Persistence

Codespaces are not intended to be treated as permanent servers.

Therefore:

- Source code must remain in GitHub.
- Configuration templates must remain in GitHub.
- Important task records should use persistent storage if required.
- Temporary browser sessions should be considered disposable.
- Secrets should be stored using GitHub's secret-management mechanisms.
- The system must be able to recreate itself from the repository.

## 22. Optional Remote Control

A future version may provide remote control through a secure interface.

Possible architecture:

```text
Android / PC
     │
     ▼
Secure Interface
     │
     ▼
Task API
     │
     ▼
Hermes
     │
     ▼
Browser
```

Potential functionality:

- Start task
- Stop task
- View status
- View logs
- Upload client data
- Approve human-intervention requests
- View screenshots
- View completed tasks

Remote access must require authentication.

## 23. Telegram Integration — Optional

Telegram may be used as a notification/control layer.

Possible commands:

```text
/start
/status
/tasks
/run <task>
/stop <task>
/logs <task>
```

Notifications:

```text
Task started
Task completed
Task failed
Human action required
```

Telegram credentials must be stored as secrets.

Telegram should not be required for the core system to operate.

## 24. Human-in-the-Loop

Hermes should stop and request human interaction whenever an action cannot safely or legitimately be automated.

Examples:

```text
CAPTCHA detected
     ↓
Pause
     ↓
Request human action
     ↓
Human completes challenge
     ↓
Resume task
```

Other situations may include:

- Unexpected account/security verification
- Ambiguous information
- Required consent
- Website workflow changes
- Sensitive irreversible action

## 25. Monitoring

The system should expose basic health information:

```text
Hermes: RUNNING
Browser: CONNECTED
AI API: CONNECTED
Current Task: task_001
Task Runtime: 03:24
Errors: 0
```

A health-check script should verify:

```text
Hermes process
Browser process
API connectivity
Filesystem
Required environment variables
```

## 26. Resource Management

The system should avoid unnecessary resource consumption.

Requirements:

- Close unused browser sessions.
- Clean temporary files.
- Limit screenshot storage.
- Limit log growth.
- Stop idle tasks when appropriate.
- Avoid unnecessary background processes.

## 27. Success Criteria

### Environment

- [ ] New Codespace can be created successfully.
- [ ] Hermes installs automatically.
- [ ] Browser installs and launches.
- [ ] Required dependencies pass health checks.

### AI

- [ ] Configured model API connects successfully.
- [ ] Hermes can receive and execute a task.

### Browser

- [ ] Hermes can launch the browser.
- [ ] Hermes can navigate an authorized test website.
- [ ] Hermes can interact with supported page elements.

### Client workflow

- [ ] Structured client data can be loaded.
- [ ] Task can be created from client data.
- [ ] Hermes can execute the authorized workflow.
- [ ] Completion status is recorded.

### Reliability

- [ ] Errors are logged.
- [ ] Failed tasks terminate cleanly.
- [ ] CAPTCHA/security challenges pause execution.
- [ ] Secrets are not exposed in Git or logs.

## 28. Development Phases

### Phase 1 — Codespace

Build:

- Dockerfile
- devcontainer.json
- Python/Node environment
- Basic setup script

### Phase 2 — Hermes

Build:

- Hermes installation
- Model configuration
- Hermes startup
- Health checks

### Phase 3 — Browser

Build:

- Chromium
- Browser automation
- Browser validation
- Screenshot support

### Phase 4 — Task Manager

Build:

- Task format
- Queue
- Task states
- Logging
- Error handling

### Phase 5 — Client Data

Build:

- JSON input
- Validation
- Secure storage
- Task generation

### Phase 6 — Authorized Website Testing

Use a controlled test workflow to verify:

- Navigation
- Form interaction
- File upload
- Error detection
- Completion reporting

### Phase 7 — Remote Interface

Optional:

- Telegram
- Web dashboard
- Mobile interface
- Status monitoring

## 29. Non-Goals

The initial version will NOT:

- Bypass CAPTCHA or anti-bot systems.
- Circumvent authentication or access controls.
- Automatically defeat website security mechanisms.
- Store credentials in source code.
- Run unlimited autonomous retries.
- Operate against websites without authorization.
- Depend on Telegram for core functionality.

## 30. Final Architecture Goal

The completed system should provide this workflow:

```text
                 GitHub
                   │
                   ▼
            GitHub Codespace
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
   Hermes Agent          Task Manager
        │                     │
        │              Client Information
        │                     │
        └──────────┬──────────┘
                   ▼
             Browser Agent
                   │
                   ▼
        Authorized Website
                   │
          ┌────────┴────────┐
          ▼                 ▼
      Completed          Human Action
        Task              Required
          │                 │
          └────────┬────────┘
                   ▼
              Logs/Status
```

The key design principle is **reproducibility**: deleting and recreating the Codespace should allow the complete Hermes environment to be rebuilt from the repository and securely supplied secrets without manually configuring the machine again.
