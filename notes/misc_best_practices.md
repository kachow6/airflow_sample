# Misc. Best Practices
Last updated 2023-09-11

## Jinja Templating

Airflow leverages Jinja templating for formatting operator commands and processes.

A Jinja template is simply a text file. Jinja can generate any text-based format (HTML, XML, CSV, LaTeX, etc.). A Jinja template doesn’t need to have a specific extension: .html, .xml, or any other extension is just fine.

A template contains variables and/or expressions, which get replaced with values when a template is rendered; and tags, which control the logic of the template. The template syntax is heavily inspired by Django and Python.

Below is a minimal template that illustrates a few basics using the default Jinja configuration. We will cover the details later in this document:

```
<!DOCTYPE html>
<html lang="en">
<head>
    <title>My Webpage</title>
</head>
<body>
    <ul id="navigation">
    {% for item in navigation %}
        <li><a href="{{ item.href }}">{{ item.caption }}</a></li>
    {% endfor %}
    </ul>

    <h1>My Webpage</h1>
    {{ a_variable }}

    {# a comment #}
</body>
</html>
```

A complete overview of Jinja LTS documentation can be found [here](https://jinja.palletsprojects.com/en/3.1.x/templates/).

You can use Jinja templating with every parameter that is marked as “templated” in the documentation. Template substitution occurs just before the `pre_execute` function of your operator is called.

```
class MyDataReader:
    template_fields: Sequence[str] = ("path",)

    def __init__(self, my_path):
        self.path = my_path

    # [additional code here...]


t = PythonOperator(
    task_id="transform_data",
    python_callable=transform_data,
    op_args=[MyDataReader("/tmp/{{ ds }}/my_file")],
    dag=dag,
)
```

You can pass custom options to the Jinja Environment when creating your DAG. One common usage is to avoid Jinja from dropping a trailing newline from a template string:

```
my_dag = DAG(
    dag_id="my-dag",
    jinja_environment_kwargs={
        "keep_trailing_newline": True,
        # some other jinja2 Environment options here
    },
)
```
**Note 1**: By default, all `template_fields` values are rendered as strings. You can pass `render_template_as_native_obj=True` to the DAG to convert this value to a Native Python Object.

**Note 2**: Add a space after the script name when directly calling a Bash script with the `BashOperator` `bash_command` kwarg.

https://airflow.apache.org/docs/apache-airflow/stable/howto/operator/bash.html#troubleshooting

## Variables

Variables are Airflow’s runtime configuration concept - a general key/value store that is global and can be queried from your tasks, and easily set via Airflow’s user interface, or bulk-uploaded as a JSON file.

```
from airflow.models import Variable

# Normal call style
foo = Variable.get("foo")

# Auto-deserializes a JSON value
bar = Variable.get("bar", deserialize_json=True)

# Returns the value of default_var (None) if the variable is not set
baz = Variable.get("baz", default_var=None)
```

* Variables are global, and should only be used for overall configuration that covers the entire installation
* Variables are really only for values that are truly runtime-dependent

Using Airflow Variables yields network calls and database access, so their usage in top-level Python code for DAGs should be avoided as much as possible:

Accessing a variable in a `BashOperator`:
```
bash_use_variable_good = BashOperator(
    task_id="bash_use_variable_good",
    bash_command="echo variable foo=${foo_env}",
    env={"foo_env": "{{ var.value.get('foo') }}"},
)
```

Accessing a variable in a Timetable interval:
```
from airflow.models.variable import Variable
from airflow.timetables.interval import CronDataIntervalTimetable


class CustomTimetable(CronDataIntervalTimetable):
    def __init__(self, *args, something="something", **kwargs):
        self._something = Variable.get(something)
        super().__init__(*args, **kwargs)
```

https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/variables.html

## Operator Environment Variables

Airflow variables can be created via the UI and can also be created and managed using Environment Variables. The environment variable naming convention is `AIRFLOW_VAR_{VARIABLE_NAME}`, all uppercase. So if your variable key is `FOO` then the variable name should be `AIRFLOW_VAR_FOO`.

```
export AIRFLOW_VAR_FOO=BAR

# To use JSON, store them as JSON strings
export AIRFLOW_VAR_FOO_BAZ='{"hello":"world"}'
```

## Dynamic Environment Variables

The key value pairs returned in `get_airflow_context_vars` defined in `airflow_local_settings.py` are injected to default airflow context environment variables, which are available as environment variables when running tasks. Note, both key and value are must be string.

```
def get_airflow_context_vars(context) -> dict[str, str]:
    """
    :param context: The context for the task_instance of interest.
    """
    # more env vars
    return {"airflow_cluster": "main"}
```

## Mocking Environment Variables

When you write tests for code that use variables or a connection, you must ensure that they exist when you run the tests. Instead of saving these objects to the database so they can be read while your code is executing, it is worth simulating the existence of these objects via environment variables with mocking `os.environ` using `unittest.mock.patch.dict()`:

```
with mock.patch.dict("os.environ", AIRFLOW_VAR_KEY="env-value"):
    assert "env-value" == Variable.get("key")
```

```
conn = Connection(
    conn_type="gcpssh",
    login="cat",
    host="conn-host",
)
conn_uri = conn.get_uri()
with mock.patch.dict("os.environ", AIRFLOW_CONN_MY_CONN=conn_uri):
    assert "cat" == Connection.get("my_conn").login
```
