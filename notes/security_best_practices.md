# Security Best Practices
Last updated 2023-09-01

## Default Roles

Airflow ships with a set of roles by default: **Admin**, **User**, **Op**, **Viewer**, and **Public**. By default, only Admin users can configure/alter permissions for roles. However, it is recommended that these default roles remain unaltered, and instead Admin users create new roles with the desired permissions if changes are necessary.

## Airflow security model - user types

The Airflow security model involves different types of users with varying access and capabilities:

  1. **Deployment Managers**: They have the highest level of access and control. They install and configure Airflow, and make decisions about technologies and permissions. They can potentially delete the entire installation and have access to all credentials. Deployment Managers can also decide to keep audits, backups and copies of information outside of Airflow, which are not covered by Airflow’s security model.

  2. **DAG Authors**: They can upload, modify, and delete DAG files. The code in DAG files is executed on workers. Therefore, DAG authors can create and change code executed on workers and potentially access the credentials that DAG code uses to access external systems. DAG Authors have full access to the metadata database and internal audit logs.

  3. **Authenticated UI users**: They have access to the UI and API. See below for more details on the capabilities authenticated UI users may have.

  4. **Non-authenticated UI users**: Airflow doesn’t support unauthenticated users by default. If allowed, potential vulnerabilities must be assessed and addressed by the Deployment Manager.

## Capabilities of authenticated UI users

The capabilities of Authenticated UI users can vary depending on what roles have been configured by the Deployment Manager or Admin users as well as what permissions those roles have. Permissions on roles can be scoped as tightly as a single DAG, for example, or as broad as Admin. Below are four general categories to help conceptualize some of the capabilities authenticated users may have:

  1. **Admin users**: They manage and grant permissions to other users, with full access to all UI capabilities. They can potentially execute code on workers by configuring connections and need to be trusted not to abuse these privileges. They have access to sensitive credentials and can modify them. By default, they don’t have access to system-level configuration. They should be trusted not to misuse sensitive information accessible through connection configuration. They also have the ability to create a Webserver Denial of Service situation and should be trusted not to misuse this capability.

  2. **Operations users**: The primary difference between an operator and admin if the ability to manage and grant permissions to other users - only admins are able to do this. Otherwise assume they have the same access as an admin.

  3. **Connection configuration users**: They configure connections and potentially execute code on workers during DAG execution. Trust is required to prevent misuse of these privileges. They have full access to sensitive credentials stored in connections and can modify them. Access to sensitive information through connection configuration should be trusted not to be abused. They also have the ability to create a Webserver Denial of Service situation and should be trusted not to misuse this capability.

  4. Normal Users: They can view and interact with the UI and API. They are able to view and edit DAGs, task instances, and DAG runs, and view task logs.

https://airflow.apache.org/docs/apache-airflow/stable/security/security_model.html

## Masking sensitive data

Airflow will by default mask Connection passwords and sensitive Variables and keys from a Connection’s extra (JSON) field when they appear in Task logs, in the Variable and in the Rendered fields views of the UI.

It does this by looking for the specific value appearing anywhere in your output. This means that if you have a connection with a password of a, then every instance of the letter a in your logs will be replaced with ***.

## Adding your own masks

If you want to mask an additional secret that is already masked by one of the above methods, you can do it in your DAG file or operator’s execute function using the mask_secret function. For example:

```
@task
def my_func():
    from airflow.utils.log.secrets_masker import mask_secret

    mask_secret("custom_value")

    ...
```

or

```
class MyOperator(BaseOperator):
    def execute(self, context):
        from airflow.utils.log.secrets_masker import mask_secret

        mask_secret("custom_value")

        ...
```

The mask must be set before any log/output is produced to have any effect.

https://airflow.apache.org/docs/apache-airflow/stable/security/secrets/mask-sensitive-values.html
