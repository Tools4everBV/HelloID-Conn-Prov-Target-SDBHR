# HelloID-Conn-Prov-Target-SDBHR

<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR/network/members"><img src="https://img.shields.io/github/forks/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR" alt="Forks Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR/pulls"><img src="https://img.shields.io/github/issues-pr/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR" alt="Pull Requests Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR/issues"><img src="https://img.shields.io/github/issues/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR" alt="Issues Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR?color=2b9348"></a>

| :information_source: Information                                                         |
| :--------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/sdbgroep-logo.png" width="500">
</p> 

## Versioning
| Version | Description     |
| ------- | --------------- |
| 1.0.0   | Initial release |

<!-- TABLE OF CONTENTS -->
## Table of Contents
- [HelloID-Conn-Prov-Target-SDBHR](#helloid-conn-prov-target-sdbhr)
  - [Versioning](#versioning)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
  - [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Connection settings](#connection-settings)
  - [Remarks](#remarks)
  - [Getting help](#getting-help)
  - [HelloID Docs](#helloid-docs)

## Requirements
- **API User** used to call the WebAPI, this is used as identifier.
- **Key** used in the authentication mechanism.
- **Customer Number** for which the request is executed, you may be authorized for multiple clients within the WebAPI therefore we always want to know which client number the requests are intended for. In many cases the customer number is equal to the user.
- **Permissions** to update the Business E-mail Address (without this a 401 unauthorized error will occur).

## Introduction
With this connector we have the option to update the emplopyees in SDB HR. This connector is designed to write back the e-mail address HelloID generated and created for e.g. Active Directory or Azure Active Directory.

| Action | Action(s) Performed | Comment |
| ------ | ------------------- | ------- |
| create.ps1                | Correlate to or Update account  | Users are only updated when this is configured, **make sure to check your configuration options to prevent unwanted actions**. |
| update.ps1                | Update account  | Update with the specified properties. The **default example sets these with the AD values**.  |
| delete.ps1                | Update account  | Update with the specified properties. The **default example sets these with the AD values**.              |

## Getting Started
To use this connector we need the **API User**, **Key** and **Customer Number**, all of which can be found at SDB Administration under Links -> WebAPI. For more information please see the [SDB API Swagger docs](https://api.sdbstart.nl/swagger/ui/index).

We also need **Permissions** to update the Business E-mail Address (without this a 401 unauthorized error will occur). This can be requested at SDB.

### Connection settings
The following settings are required to connect to the API.

| Setting | Description | Mandatory |
| ------- | ----------- | --------- |
| Base URI  | The BaseURI of the API endpoint(s). Can be found at [SDB API Swagger docs](https://api.sdbstart.nl/swagger/ui/index) | Yes |
| Api User  | The user used to call the WebAPI, this is used as identifier | Yes  |
| API Key | The key used in the authentication mechanism | Yes |
| App Secret  | The Application  | Yes  |
| CustomerNumber  | The customer number for which the request is executed, you may be authorized for multiple clients within the WebAPI therefore we always want to know which client number the requests are intended for. In many cases the customer number is equal to the user. | Yes |
| Update account when correlating and mapped data differs | When toggled, the acount will be updated when the mapped HelloID data differs from the data in the target system in the create action (not just correlate). | No  |
| Toggle debug logging  | When toggled, debug logging will be displayed. **Note that this is only meant for debugging, please switch this off when in production.** | No  |

## Remarks
- Best practice is to clear the Business E-mail Address when deleting the corresponding account or mailbox. This way the value in SDB always represents the truth.

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012518799-How-to-add-a-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/806-helloid-provisioning-helloid-conn-prov-target-exchangeonline)_

## HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/
