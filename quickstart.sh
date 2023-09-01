source apache_airflow/bin/activate
export AIRFLOW_HOME=~/airflow
airflow db init
airflow webserver -p 8081
