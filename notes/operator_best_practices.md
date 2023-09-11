# Basic Best Practices
Last updated 2023-09-07

## Hooks

Hooks act as an interface to communicate with the external shared resources in a DAG. For example, multiple tasks in a DAG can require access to a MySQL database. Instead of creating a connection per task, you can retrieve a connection from the hook and utilize it. Hook also helps to avoid storing connection auth parameters in a DAG. See Managing Connections for how to create and manage connections and Provider packages for details of how to add your custom connection types via providers.

```
class HelloDBOperator(BaseOperator):
    def __init__(self, name: str, mysql_conn_id: str, database: str, **kwargs) -> None:
        super().__init__(**kwargs)
        self.name = name
        self.mysql_conn_id = mysql_conn_id
        self.database = database

    def execute(self, context):
        hook = MySqlHook(mysql_conn_id=self.mysql_conn_id, schema=self.database)
        sql = "select name from user"
        result = hook.get_first(sql)
        message = f"Hello {result['name']}"
        print(message)
        return message
```

https://airflow.apache.org/docs/apache-airflow/stable/howto/custom-operator.html#hooks

## Custom Operators

Airflow allows you to create new operators to suit the requirements of you or your team. This extensibility is one of the many features which make Apache Airflow powerful.

There are two methods that you need to override in a derived class:

* **Constructor** - Define the parameters required for the operator. You only need to specify the arguments specific to your operator. You can specify the default_args in the DAG file. See Default args for more details.

* **Execute** - The code to execute when the runner calls the operator. The method contains the Airflow context as a parameter that can be used to read config values.

```
from airflow.models.baseoperator import BaseOperator


class HelloOperator(BaseOperator):

    # You can use Jinja templates to parameterize your operator:
    template_fields: Sequence[str] = ("name",)

    def __init__(self, name: str, **kwargs) -> None:
        super().__init__(**kwargs)
        self.name = name

    def execute(self, context):
        message = f"Hello {self.name}"
        print(message)
        return message
```

```
with dag:
    hello_task = HelloOperator(
        task_id="task_id_1",
        name="{{ task_instance.task_id }}",
        world="Earth",
    )
```

If an operator communicates with an external service (API, database, etc) it’s a good idea to implement the communication layer using a Hook. In this way the implemented logic can be reused by other users in different operators. Such approach provides better decoupling and utilization of added integration than using CustomServiceBaseOperator for each external service.

**Note 1**: The `params` variable is used during DAG serialization and is a reserved word that should be avoided in third party operators

**Note 2**: It is possible to add custom `@task` decorators - https://airflow.apache.org/docs/apache-airflow/stable/howto/create-custom-decorator.html

https://airflow.apache.org/docs/apache-airflow/stable/howto/custom-operator.html#

## Sensor Operators

Airflow provides a primitive for a special kind of operator, whose purpose is to poll some state (e.g. presence of a file) on a regular interval until a success criteria is met.

Because they are primarily idle, Sensors have two different modes of running so you can be a bit more efficient about using them:

* **poke** (default): The Sensor takes up a worker slot for its entire runtime
* **reschedule**: The Sensor takes up a worker slot only when it is checking, and sleeps for a set duration between checks

The poke and reschedule modes can be configured directly when you instantiate the sensor; generally, the trade-off between them is latency. Something that is checking every second should be in poke mode, while something that is checking every minute should be in reschedule mode.

You can create any sensor your want by extending the `airflow.sensors.base.BaseSensorOperator` defining a `poke()` method to poll your external state and evaluate the success criteria.

You can apply the `@task.sensor` decorator to convert a regular Python function to an instance of the `BaseSensorOperator` class. The Python function implements the poke logic and returns an instance of the `PokeReturnValue` class as the `poke()` method in the `BaseSensorOperator` does. In Airflow `2.3`, sensor operators will be able to return XCOM values. This is achieved by returning an instance of the `PokeReturnValue` object at the end of the `poke()` method:

```
from airflow.sensors.base import PokeReturnValue


class SensorWithXcomValue(BaseSensorOperator):
    def poke(self, context: Context) -> Union[bool, PokeReturnValue]:
        # ...
        is_done = ...  # set to true if the sensor should stop poking.
        xcom_value = ...  # return value of the sensor operator to be pushed to XCOM.
        return PokeReturnValue(is_done, xcom_value)
```

https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/sensors.html

https://airflow.apache.org/docs/apache-airflow/stable/tutorial/taskflow.html#using-the-taskflow-api-with-sensor-operators

## Custom Objects

It is possible to pass custom objects to tasks. Typically you would decorate your classes with `@dataclass` or `@attr.define` and Airflow will figure out what it needs to do. To do so add the `serialize()` method to your class and the staticmethod `deserialize(data: dict, version: int)` to your class.

```
from typing import ClassVar


class MyCustom:
    __version__: ClassVar[int] = 1

    def __init__(self, x):
        self.x = x

    def serialize(self) -> dict:
        return dict({"x": self.x})

    @staticmethod
    def deserialize(data: dict, version: int):
        if version > 1:
            raise TypeError(f"version > {MyCustom.version}")
        return MyCustom(data["x"])
```

## Notifications

### Listener Plugins

Airflow has feature that allows to add listener for monitoring and tracking the task state using Plugins. These can be used for things like tracking task states and collecting metadata about tasks, DAG runs, and DAGs.

```
from airflow.plugins_manager import AirflowPlugin

# This is the listener file created where custom code to monitor is added over hookimpl
import listener


class MetadataCollectionPlugin(AirflowPlugin):
    name = "MetadataCollectionPlugin"
    listeners = [listener]
```

listener code:
```
@hookimpl
def on_task_instance_running(previous_state: TaskInstanceState, task_instance: TaskInstance, session):
    """
    This method is called when task state changes to RUNNING.
    Through callback, parameters like previous_task_state, task_instance object can be accessed.
    This will give more information about current task_instance that is running its dag_run,
    task and dag information.
    """
    print("Task instance is in running state")
    print(" Previous state of the Task instance:", previous_state)

    state: TaskInstanceState = task_instance.state
    name: str = task_instance.task_id
    start_date = task_instance.start_date

    dagrun = task_instance.dag_run
    dagrun_status = dagrun.state

    task = task_instance.task

    dag = task.dag
    dag_name = None
    if dag:
        dag_name = dag.dag_id
    print(f"Current task name:{name} state:{state} start_date:{start_date}")
    print(f"Dag name:{dag_name} and current dag run status:{dagrun_status}")
```

https://airflow.apache.org/docs/apache-airflow/stable/howto/listener-plugin.html

### Creating Notifiers

The `BaseNotifier` is an abstract class that provides a basic structure for sending notifications in Airflow using the various `on_*__callback`. It is intended for providers to extend and customize for their specific needs:


BaseNotifier creation:
```
from airflow.notifications.basenotifier import BaseNotifier
from my_provider import send_message


class MyNotifier(BaseNotifier):
    template_fields = ("message",)

    def __init__(self, message):
        self.message = message

    def notify(self, context):
        # Send notification here, below is an example
        title = f"Task {context['task_instance'].task_id} failed"
        send_message(title, self.message)
```

BaseNotifier usage:
```
from datetime import datetime

from airflow.models.dag import DAG
from airflow.operators.bash import BashOperator

from myprovider.notifier import MyNotifier

with DAG(
    dag_id="example_notifier",
    start_date=datetime(2022, 1, 1),
    schedule_interval=None,
    on_success_callback=MyNotifier(message="Success!"),
    on_failure_callback=MyNotifier(message="Failure!"),
):
    task = BashOperator(
        task_id="example_task",
        bash_command="exit 1",
        on_success_callback=MyNotifier(message="Task Succeeded!"),
    )
```

https://airflow.apache.org/docs/apache-airflow/stable/howto/notifications.html

## Timetables

DAG scheduling is useful with Timetables if a cron expression or timedelta object is not enough to express your DAG’s schedule, logical date, or data interval (e.g. days of the week and holidays). Timetables must be a subclass of `Timetable` and should be registered as part of a plugin:

```
from airflow.plugins_manager import AirflowPlugin
from airflow.timetables.base import Timetable


class AfterWorkdayTimetable(Timetable):
    pass


class WorkdayTimetablePlugin(AirflowPlugin):
    name = "workday_timetable_plugin"
    timetables = [AfterWorkdayTimetable]
```

```
import pendulum

from airflow import DAG
from airflow.example_dags.plugins.workday import AfterWorkdayTimetable


with DAG(
    dag_id="example_after_workday_timetable_dag",
    start_date=pendulum.datetime(2021, 3, 10, tz="UTC"),
    schedule=AfterWorkdayTimetable(),
    tags=["example", "timetable"],
):
    ...
```

https://airflow.apache.org/docs/apache-airflow/stable/howto/timetable.html

## Timeouts

If you want a task to have a maximum runtime, set its `execution_timeout` attribute to a `datetime.timedelta` value that is the maximum permissible runtime. This applies to all Airflow tasks, including sensors. `execution_timeout` controls the maximum time allowed for every execution. If `execution_timeout` is breached, the task times out and `AirflowTaskTimeout` is raised.

In addition, sensors have a `timeout` parameter. This only matters for sensors in `reschedule` mode. `timeout` controls the maximum time allowed for the sensor to succeed. If `timeout` is breached, `AirflowSensorTimeout` will be raised and the sensor fails immediately without retrying.

```
sensor = SFTPSensor(
    task_id="sensor",
    path="/root/test",
    execution_timeout=timedelta(seconds=60),
    timeout=3600,
    retries=2,
    mode="reschedule",
)
```

https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/tasks.html#timeouts

## SLAs

An SLA, or a Service Level Agreement, is an expectation for the maximum time a Task should be completed relative to the Dag Run start time. If a task takes longer than this to run, it is then visible in the “SLA Misses” part of the user interface, as well as going out in an email of all tasks that missed their SLA.

Tasks over their SLA are not cancelled, though - they are allowed to run to completion.

To set an SLA for a task, pass a `datetime.timedelta` object to the Task/Operator’s `sla` parameter. You can also supply an `sla_miss_callback` that will be called when the SLA is missed if you want to run your own logic.

**Note**: Manually-triggered tasks and tasks in event-driven DAGs will not be checked for an SLA miss

https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/tasks.html#slas

## Special Exceptions

If you want to control your task’s state from within custom Task/Operator code, Airflow provides two special exceptions you can raise:

* **AirflowSkipException** will mark the current task as skipped
* **AirflowFailException** will mark the current task as failed ignoring any remaining retry attempts

## Logging

To use logging from your task functions, simply import and use Python’s logging system:

```
logger = logging.getLogger("airflow.task")
```

