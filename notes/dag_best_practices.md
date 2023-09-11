# DAG Best Practices
Last updated 2023-09-11

## TaskFlow API (Airflow 2.0)

The TaskFlow API makes it much easier to write clean DAGs without extra boilerplate using the `@task` decorator, using plain Python code instead of Operator syntax.

### Passing Data Between Tasks

Typically in Airflow 1.0, data is passed between tasks via the [XComs](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/xcoms.html) (cross-communications) mechansim. Note this requires that variables that are used as arguments need to be able to be serialized. This logic is abstracted in Airflow 2.0 via the [TaskFlow API](https://airflow.apache.org/docs/apache-airflow/stable/tutorial/taskflow.html):

> Airflow 2.0 provides a decorator @task that internally transforms any Python function into a PythonOperator. Tasks created this way can share data with each other. If you hear about this feature for the first time, it seems almost too good to be true:
>
> 1. new Airflow users no longer have to learn Airflow’s specific operators to build their data pipelines,
> 2. you can finally pass data from one task to another without having to write any tedious XComs logic

https://medium.com/@diogo22santos/the-past-present-and-future-of-data-architecture-bd23dea0654b

### Complex/Conflicting Python Dependencies

If you have tasks that require complex or conflicting requirements then you will have the ability to use the TaskFlow API with either Python virtual environment (since 2.0.2), Docker container (since 2.2.0), ExternalPythonOperator (since 2.4.0) or KubernetesPodOperator (since 2.4.0).

Which of the operators you should use, depend on several factors:

* whether you are running Airflow with access to Docker engine or Kubernetes
* whether you can afford an overhead to dynamically create a virtual environment with the new dependencies
* whether you can deploy a pre-existing, immutable Python environment for all Airflow components.

https://airflow.apache.org/docs/apache-airflow/stable/tutorial/taskflow.html#tasks

https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html#handling-conflicting-complex-python-dependencies

### Handling Python Imports

One of the important factors impacting DAG loading time, that might be overlooked by Python developers is that top-level imports might take surprisingly a lot of time and they can generate a lot of overhead and this can be easily avoided by converting them to local imports inside Python callables for example.

```
import pendulum

from airflow import DAG
from airflow.decorators import task

with DAG(
    dag_id="example_python_operator",
    schedule=None,
    start_date=pendulum.datetime(2021, 1, 1, tz="UTC"),
    catchup=False,
    tags=["example"],
) as dag:

    @task()
    def print_array():
        """Print Numpy array."""
        import numpy as np  # <- THIS IS HOW NUMPY SHOULD BE IMPORTED IN THIS CASE!

        a = np.arange(15).reshape(3, 5)
        print(a)
        return a

    print_array()
```

https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html#top-level-python-code

## DAG Packaging

While simpler DAGs are usually only in a single Python file, it is not uncommon that more complex DAGs might be spread across multiple files and have dependencies that should be shipped with them (“vendored”).

```
my_dag1.py
my_dag2.py
package1/__init__.py
package1/functions.py
```

### `.airflowignore`

An `.airflowignore` file specifies the directories or files in `DAG_FOLDER` or `PLUGINS_FOLDER` that Airflow should intentionally ignore.

https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html#packaging-dags

## Dynamic DAG Generation

If you want to use variables to configure your code, you should always use environment variables in your top-level code rather than Airflow Variables.

```
deployment = os.environ.get("DEPLOYMENT", "PROD")
if deployment == "PROD":
    task = Operator(param="prod-param")
elif deployment == "DEV":
    task = Operator(param="dev-param")
```

Note:
> In all cases where you generate DAGs dynamically, you should make sure that Tasks and Task Groups are generated with consistent sequence every time the DAG is generated, otherwise you might end up with Tasks and Task Groups changing their sequence in the Grid View every time you refresh the page. This can be achieved for example by using a stable sorting mechanism in your Database queries or by using sorted() function in Python.

### Generating Python code with metadata

Importable constants can be imported directly by your DAG and used to construct objects and build dependencies:

`my_company_utils/common.py`
```
# This file is generated automatically !
ALL_TASKS = ["task1", "task2", "task3"]
```

DAG file:
```
from my_company_utils.common import ALL_TASKS

with DAG(
    dag_id="my_dag",
    schedule=None,
    start_date=datetime(2021, 1, 1),
    catchup=False,
):
    for task in ALL_TASKS:
        # create your operators and relations here
        ...
```

In this case you need to add empty `__init__.py` file in the `my_company_utils` folder and you should add the `my_company_utils/.*` line to `.airflowignore` file (if using the regexp ignore syntax), so that the whole folder is ignored by the scheduler when it looks for DAGs.

https://airflow.apache.org/docs/apache-airflow/stable/howto/dynamic-dag-generation.html

## Timezones

Airflow DAGs implement timezone logic using the `pendulum` library. Do not use the standard `timezone` library.

## SubDAGs

SubDAG is deprecated hence TaskGroup is always the preferred choice.

## Setup and Teardown 

In data workflows it’s common to create a resource (such as a compute resource), use it to do some work, and then tear it down. Airflow provides setup and teardown tasks to support this need - `as_setup()` and `as_teardown()` methods.

Key features of setup and teardown tasks:

- If you clear a task, its setups and teardowns will be cleared.
- By default, teardown tasks are ignored for the purpose of evaluating dag run state.
- A teardown task will run if its setup was successful, even if its work tasks failed.
- Teardown tasks are ignored when setting dependencies against task groups.
- You can have a setup without a teardown.

### Examples

Basic implementation:

```
create_cluster.as_setup() >> run_query >> delete_cluster.as_teardown()
create_cluster >> delete_cluster
```

One-liner method:

```
create_cluster >> run_query >> delete_cluster.as_teardown(setups=create_cluster)
```

Multiple tasks using same setup and teardown context managers:

```
with delete_cluster().as_teardown(setups=create_cluster()):
    [RunQueryOne(), RunQueryTwo()] >> DoSomeOtherStuff()
    WorkOne() >> [do_this_stuff(), do_other_stuff()]
```

![Complex setup/teardown multi-task context management](https://airflow.apache.org/docs/apache-airflow/stable/_images/setup-teardown-complex.png)

Nested TaskGroup with multiple setup and teardown tasks:

```
with TaskGroup("my_group") as tg:
    s1 = s1()
    w1 = w1()
    t1 = t1()
    s1 >> w1 >> t1.as_teardown(setups=s1)
w2 = w2()
tg >> w2
dag_s1 = dag_s1()
dag_t1 = dag_t1()
dag_s1 >> [tg, w2] >> dag_t1.as_teardown(setups=dag_s1)
```

![Nested setup/teardown multi-task context management](https://airflow.apache.org/docs/apache-airflow/stable/_images/setup-teardown-nesting.png)

Running multiple setup and teardown tasks in parallel:

```
with TaskGroup("setup") as tg_s:
    create_cluster = create_cluster()
    create_bucket = create_bucket()
run_query = run_query()
with TaskGroup("teardown") as tg_t:
    delete_cluster = delete_cluster().as_teardown(setups=create_cluster)
    delete_bucket = delete_bucket().as_teardown(setups=create_bucket)
tg_s >> run_query >> tg_t
```

![Parallel setup/teardown tasks](https://airflow.apache.org/docs/apache-airflow/stable/_images/setup-teardown-setup-group.png)

### Task Failure Workflows

If you want to trigger task based on another task's failure without introducing a teardown task, you can set the `trigger_rule` to `TriggerRule.ALL_FAILED` if the task execution depends on the failure of ALL its upstream tasks or `TriggerRule.ONE_FAILED` for just one of the upstream task:

```
import pendulum

from airflow.decorators import dag, task
from airflow.exceptions import AirflowException
from airflow.utils.trigger_rule import TriggerRule


@task()
def a_func():
    raise AirflowException


@task(
    trigger_rule=TriggerRule.ALL_FAILED,
)
def b_func():
    pass


@dag(schedule="@once", start_date=pendulum.datetime(2021, 1, 1, tz="UTC"))
def my_dag():
    a = a_func()
    b = b_func()

    a >> b


dag = my_dag()
```

https://airflow.apache.org/docs/apache-airflow/stable/howto/setup-and-teardown.html#

https://airflow.apache.org/docs/apache-airflow/stable/faq.html#how-to-trigger-tasks-based-on-another-task-s-failure

## Watcher DAG Design Pattern

If we want to ensure that a DAG with teardown task would fail if any task fails, we need to use the watcher pattern.

The watcher task is a task that will always fail if triggered, but it needs to be triggered only if any other task fails. It needs to have a trigger rule set to `TriggerRule.ONE_FAILED` and it needs also to be a downstream task for all other tasks in the DAG. If every other task passes, the watcher will be skipped, but when something fails, the watcher task will be executed and fail, making the DAG Run fail too.

```
from datetime import datetime

from airflow import DAG
from airflow.decorators import task
from airflow.exceptions import AirflowException
from airflow.operators.bash import BashOperator
from airflow.utils.trigger_rule import TriggerRule


@task(trigger_rule=TriggerRule.ONE_FAILED, retries=0)
def watcher():
    raise AirflowException("Failing task because one or more upstream tasks failed.")


with DAG(
    dag_id="watcher_example",
    schedule="@once",
    start_date=datetime(2021, 1, 1),
    catchup=False,
) as dag:
    failing_task = BashOperator(task_id="failing_task", bash_command="exit 1", retries=0)
    passing_task = BashOperator(task_id="passing_task", bash_command="echo passing_task")
    teardown = BashOperator(
        task_id="teardown",
        bash_command="echo teardown",
        trigger_rule=TriggerRule.ALL_DONE,
    )

    failing_task >> passing_task >> teardown
    list(dag.tasks) >> watcher()
```

## DAG Optimization Techniques

DAG suite configuration performance can be modified utilising the following features:

- parallelism
- max_active_tasks_per_dag
- max_active_runs_per_dag

Large suites with > 1000 DAG files can optimize file parsing via:

- file_parsing_sort_mode
- min_file_process_interval

There are no “metrics” for individual DAG complexity, especially, there are no metrics that can tell you whether your DAG is “simple enough”. However, as with any Python code, you can definitely tell that your DAG code is “simpler” or “faster” when it is optimized.

* Make your DAG load faster. This is a single improvement advice that might be implemented in various ways but this is the one that has biggest impact on scheduler’s performance.
* Make your DAG generate simpler structure. Every task dependency adds additional processing overhead for scheduling and execution
* Make smaller number of DAGs per file. While Airflow 2 is optimized for the case of having multiple DAGs in one file, there are some parts of the system that make it sometimes less performant, or introduce more delays than having those DAGs split among many files.
* Write efficient Python code. A balance must be struck between fewer DAGs per file, as stated above, and writing less code overall. Creating the Python files that describe DAGs should follow best programming practices and not be treated like configurations.

https://airflow.apache.org/docs/apache-airflow/stable/faq.html#how-to-improve-dag-performance

https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html#reducing-dag-complexity

## DAG Testing Strategies

### Load Testing

This test should ensure that your DAG does not contain a piece of code that raises error while loading:
```
python <your-dag-file>.py
```

This command should be run in a container that is simulated to be as close as possible to a live environment. An easy way to test DAG optimizations is to run the above command several times (accounts for caching effects) using the built in Linux `time` command, measuring the `real` time execution:

```
time python airflow/example_dags/example_python_operator.py
```

Result:
```
real    0m0.699s
user    0m0.590s
sys     0m0.108s
```

Note: This method starts a new interpreter process whose time can be accounted for by running the below command and subtracting it from the above time:

```
time python -c ''
```

### Unit Testing

You can implement automated unit test load testing via the `pytest` library:

```
import pytest

from airflow.models import DagBag


@pytest.fixture()
def dagbag():
    return DagBag()


def test_dag_loaded(dagbag):
    dag = dagbag.get_dag(dag_id="hello_world")
    assert dagbag.import_errors == {}
    assert dag is not None
    assert len(dag.tasks) == 1
```

Testing a dynamically generating DAG against a dict object:

```
def assert_dag_dict_equal(source, dag):
    assert dag.task_dict.keys() == source.keys()
    for task_id, downstream_list in source.items():
        assert dag.has_task(task_id)
        task = dag.get_task(task_id)
        assert task.downstream_task_ids == set(downstream_list)


def test_dag():
    assert_dag_dict_equal(
        {
            "DummyInstruction_0": ["DummyInstruction_1"],
            "DummyInstruction_1": ["DummyInstruction_2"],
            "DummyInstruction_2": ["DummyInstruction_3"],
            "DummyInstruction_3": [],
        },
        dag,
    )
```

Unit tests for a custom operator:

```
import datetime

import pendulum
import pytest

from airflow import DAG
from airflow.utils.state import DagRunState, TaskInstanceState
from airflow.utils.types import DagRunType

DATA_INTERVAL_START = pendulum.datetime(2021, 9, 13, tz="UTC")
DATA_INTERVAL_END = DATA_INTERVAL_START + datetime.timedelta(days=1)

TEST_DAG_ID = "my_custom_operator_dag"
TEST_TASK_ID = "my_custom_operator_task"


@pytest.fixture()
def dag():
    with DAG(
        dag_id=TEST_DAG_ID,
        schedule="@daily",
        start_date=DATA_INTERVAL_START,
    ) as dag:
        MyCustomOperator(
            task_id=TEST_TASK_ID,
            prefix="s3://bucket/some/prefix",
        )
    return dag


def test_my_custom_operator_execute_no_trigger(dag):
    dagrun = dag.create_dagrun(
        state=DagRunState.RUNNING,
        execution_date=DATA_INTERVAL_START,
        data_interval=(DATA_INTERVAL_START, DATA_INTERVAL_END),
        start_date=DATA_INTERVAL_END,
        run_type=DagRunType.MANUAL,
    )
    ti = dagrun.get_task_instance(task_id=TEST_TASK_ID)
    ti.task = dag.get_task(task_id=TEST_TASK_ID)
    ti.run(ignore_ti_state=True)
    assert ti.state == TaskInstanceState.SUCCESS
    # Assert something related to tasks results.
```
