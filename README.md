# airflow_sample

Sample project demonstrating [Apache Airflow](https://airflow.apache.org/) virtual environment configuration and setup (MacOS). Experimentation with Airflow DAGs and ETL data pipelines.

## Quickstart

Refer to [Initial Project Setup](#initial-project-setup) and [User Configuration](#user-configuration) sections when setting up this project for the first time.

1. Run the following commands:
```
source apache_airflow/bin/activate
export AIRFLOW_HOME=~/airflow
airflow webserver -p 8081
```

Alternatively, run:
```
bash quickstart.sh
```

2. Start airflow scheduler in a separate terminal:
```
source apache_airflow/bin/activate
airflow scheduler
```

Alternatively, run:
```
bash scheduler.sh
```

3. Start airflow enabled virtual environment:
```
source apache_airflow/bin/activate
```

## Initial Project Setup

1. Setup apache airflow virtual environment
```
virtualenv apache_airflow
```

2. Activate virtual environment
```
source apache_airflow/bin/activate
```

3. Set airflow home path
```
export AIRFLOW_HOME=~/airflow
```

4. Install apache-airflow
```
pip install apache-airflow
```

5. Initialize airflow database
```
airflow db init
```

6. Start airflow web server
```
airflow webserver -p 8081
```

7. View virtualized airflow instance
```
http://localhost:8081/
```

## User Configuration

Create a new admin user
```
airflow users create -e <email> -f <first_name> -l <last_name> -p <password> -r Admin -u <user_name>
```
```
airflow users create -e kevin@example.com -f Kevin -l Chow -p 123 -r Admin -u kevin
```

## Sources

https://blog.knoldus.com/apache-airflow-installation-guide-and-basic-commands/
