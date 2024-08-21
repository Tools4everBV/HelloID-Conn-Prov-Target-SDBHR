# HelloID-Conn-Prov-Target-SDBHR

> [!IMPORTANT]
> This repository contains only the connector and configuration code. The implementer is responsible for acquiring connection details such as the username, password, certificate, etc. You may also need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-SDBHR/blob/main/Logo.png?raw=true" alt="SDBHR Logo">
</p>

## Table of Contents

- [HelloID-Conn-Prov-Target-SDBHR](#helloid-conn-prov-target-sdbhr)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
  - [Remarks](#remarks)
    - [Handling Null Values in Field Mapping](#handling-null-values-in-field-mapping)
    - [Clearing Business Email Addresses](#clearing-business-email-addresses)
  - [Introduction](#introduction)
    - [Actions](#actions)
  - [Getting Started](#getting-started)
    - [Correlation Configuration](#correlation-configuration)
    - [Connection Settings](#connection-settings)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Requirements

- **API User**: The identifier used to call the WebAPI.
- **API Key**: Used in the authentication process.
- **Customer Number**: The number associated with the client for which the request is executed. Multiple clients may be authorized within the WebAPI, and the customer number is often the same as the user.
- **Permissions**: Required to update the Business Email Address. Without these, a 401 unauthorized error will occur.

## Remarks

### Handling Null Values in Field Mapping

- The script filters out all field mappings with the value `$null`. If a value in the HelloID person model is `$null`, it is also filtered out. If you want to include these fields, modify the mapping to complex and ensure a string with a `space` or `empty` is returned when the value is `$null`. This ensures the script handles the value correctly.

### Clearing Business Email Addresses

- It is best practice to clear the Business Email Address when deleting the corresponding account or mailbox. This keeps the data in SDB HR accurate.

## Introduction

This connector allows you to update employee information in SDB HR. It is primarily used to write back the email address that HelloID generates for systems like Active Directory or Azure Active Directory.

The following API endpoints are utilized by this connector:

| Endpoint                                                                                                                               | Description       |
| -------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
| [/api/medewerkersbasic/{personeelsNummer}/{datum}](https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_GetMedewerkerV2) | Get a user (GET)  |
| [/api/medewerkers/{personeelsNummer}/{beginDatum}](https://api.sdbstart.nl/swagger/ui/index#!/Medewerkers/Medewerkers_Put)             | Update user (PUT) |

### Actions

| Action       | Description             | Comment                                                                                                               |
| ------------ | ----------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `create.ps1` | Correlate to an account | Correlation is only possible on `personeelsNummer`. **Ensure proper correlation setup** to prevent incorrect matches. |
| `delete.ps1` | Delete an account       | Updates the specified properties. The **default field mapping clears the Business Email address**.                    |
| `update.ps1` | Update an account       | Updates the specified properties. The **default field mapping sets the Business Email address with the AD mail**.     |

## Getting Started

This connector enables seamless updates to the business email addresses of employees in SDB HR.

Connecting to the SDB HR API is straightforward. You will need the **API User**, **API Key**, and **Customer Number**, all of which can be found in the SDB Administration under Links -> WebAPI. For more details, refer to the [SDB API Swagger documentation](https://api.sdbstart.nl/swagger/ui/index).

**Permissions** are also required to update the Business Email Address. Without these, a 401 unauthorized error will occur. These permissions can be requested from SDB.

### Correlation Configuration

The correlation configuration specifies which properties will be used to match an existing employee in _SDB HR_ to a person in _HelloID_.

To properly set up correlation:

1. Open the `Correlation` tab.
2. Use the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |
    | Account correlation field | `personeelsNummer`                |

> [!IMPORTANT]
> Only `personeelsNummer` is supported as the account correlation field.

> [!TIP]
> For more information on correlation, see our [correlation documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html).

### Connection Settings

The following settings are required to connect to the API.

| Setting              | Description                                                                                                        | Mandatory |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ | --------- |
| Base URI             | The Base URI of the API endpoint(s). Found in the [SDB API Swagger docs](https://api.sdbstart.nl/swagger/ui/index) | Yes       |
| API User             | The user used to call the WebAPI, serving as an identifier                                                         | Yes       |
| API Key              | The key used in the authentication mechanism                                                                       | Yes       |
| Customer Number      | The customer number for which the request is executed, usually equal to the user                                   | Yes       |
| Toggle debug logging | Displays debug logging when toggled. **Switch off in production**                                                  | No        |

## Getting help
> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs
The official HelloID documentation can be found at: https://docs.helloid.com/
