---
title: Introduction to Oracle SQL*Loader and Its Applications
date: 2023-09-09 22:57:01
tags: 数据同步
categories: 数据库
lang: en
label: 043_oracle_sqlloader
---

-----

`Oracle SQL*Loader` is a utility in the `Oracle` database management system for loading large volumes of data from external files into an `Oracle` database. It's fast, flexible, and handles a variety of formats and file types. This article covers the basics of `SQL*Loader`, how it works, and practical use cases.

<!-- more -->
#### 1. What is SQL*Loader?

`SQL*Loader` is a data import utility that loads data from plain text files, `CSV` files, and other external sources into `Oracle` database tables. It ships as a standard tool with `Oracle` Database and handles large-scale data loading without much fuss.

#### 2. How SQL*Loader Works

The workflow is straightforward:

* **Control file definition**: Write a control file specifying the target table, field mappings, data format, and other details. The control file is one of `SQL*Loader`'s core configuration files;

* **Prepare the external data file**: Prepare a file containing the data to be loaded — plain text, `CSV`, or other supported formats;

* **Run SQL\*Loader**: Execute `SQL*Loader` from the command line or another interface, specifying the control file and data file locations. `SQL*Loader` loads data into the target table per the control file;

* **Data loading**: `SQL*Loader` parses the external data file row by row based on the control file rules and inserts the data into the target table;

#### 3. SQL*Loader Control File

Here's a sample control file template:

```
LOAD DATA
INFILE 'data.csv'       -- Path to the external data file
INTO TABLE employees    -- Target table name
CHARACTERSET UTF8       -- Character set encoding of the external data file
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'   -- Field delimiter and optional enclosure character
( 
  employee_id,          -- Target table column name
  first_name,
  last_name,
  email,
  hire_date DATE 'YYYY-MM-DD'  -- Date formatting to ensure correct parsing
)
WHEN (hire_date >= '2022-02-01')
```

- `LOAD DATA` declares the start of the data loading process;
- `INFILE 'data.csv'` specifies the path to the external data file. Replace `data.csv` with the actual filename and ensure the path is correct;
- `INTO TABLE employees` specifies the target table as `employees`. Replace with your actual table name;
- `CHARACTERSET UTF8` sets the character encoding of the external file to `UTF-8`;
- `FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'` defines the field delimiter and optional enclosure character. In this example, fields are comma-separated and optionally wrapped in double quotes. Adjust these for your actual data;
- `(employee_id, first_name, last_name, email, hire_date DATE 'YYYY-MM-DD')` defines the columns to load and their data types. Make sure they match the target table's column names and types. Here, `hire_date` is formatted as a date with an explicit format mask;
- `WHEN (hire_date >= '2022-01-01')` defines a filter condition — only rows satisfying this condition get loaded into the `Oracle` database;

#### 4. SQL*Loader Use Cases

`SQL*Loader` has broad practical applications:

- **Data migration and import**: When moving data from external sources into an `Oracle` database, `SQL*Loader` is a solid choice. Its flexible configuration handles large data volumes;
- **Data integration and synchronization**: In integration scenarios, `SQL*Loader` consolidates data from different systems or sources into a single database for analysis and reporting;
- **Routine data loading**: Fetch data from external systems and load it into `Oracle` for further processing. `SQL*Loader` can automate this pipeline and keep throughput high;

#### 5. Practical Example

Here's a simple walkthrough showing how to load a `CSV` file into an `Oracle` table using `SQL*Loader`:

* Create a control file `data.ctl` defining the target table and field mappings:

```
LOAD DATA
INFILE 'data.csv'
INTO TABLE employees
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
( employee_id,
  first_name,
  last_name,
  email,
  hire_date DATE 'YYYY-MM-DD'
)
WHEN (hire_date >= '2022-02-01')
```

* Prepare the external data file `data.csv` with the data to load.

| employee_id | first_name | last_name | email              | hire_date  |
| ----------- | ---------- | --------- | ------------------ | ---------- |
| 001         | Zhang      | San       | zhangsan@gmail.com | 2023-02-01 |
| 002         | Li         | Si        | lisi@gmail.com     | 2023-02-02 |

* Run `SQL*Loader` from the command line:

```cmd
sqlldr username/password@database control=data.ctl
```

`SQL*Loader` will load the data from `data.csv` into the `employees` table.

#### 6. Conclusion

`Oracle SQL*Loader` is a solid data loading utility for importing external data into `Oracle` databases. With straightforward configuration and commands, it handles large-scale loads and keeps data processing pipelines moving.
