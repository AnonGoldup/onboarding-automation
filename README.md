# Onboarding Automation with Power Automate + Microsoft 365

## Overview

This project automates the new employee onboarding process using Microsoft 365 tools and Power Automate. It reduces manual effort by creating users, assigning licenses, adding them to groups, and provisioning initial IT resources like email, Teams access, and SharePoint permissions.

## Tools Used

- Power Automate (Cloud Flows)
- Microsoft Graph API
- Azure Active Directory / Entra ID
- SharePoint Online
- PowerShell (optional extensions)

## Key Features

- User Creation: Automatically creates new Entra ID (Azure AD) users based on SharePoint form input or Excel list
- License Assignment: Assigns Microsoft 365 licenses automatically
- Group Membership: Adds users to Teams, Distribution Lists, and Security Groups
- Notifications: Sends IT a summary email and Teams alert on completion
- Error Handling: Logs failures and missing fields to SharePoint for follow-up
- Scalability: Modular design allows integration with HRIS or ticketing systems

## Flow Diagram

![Flow Diagram](./flow-diagram.png)

## Outcomes

- Reduced onboarding time from 30–60 minutes to under 5 minutes per user
- Eliminated manual errors and inconsistencies in account setup
- Provided a repeatable, auditable workflow across departments

## Next Steps

- Extend flow to handle offboarding and device assignment
- Integrate with IT asset manager for provisioning laptops and phones
- Add reporting dashboards using Power BI

## License

MIT License – feel free to reuse and modify.
