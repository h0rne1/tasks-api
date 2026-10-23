# Сервис задач — CRUD API + PostgreSQL в Docker Compose

Контрольная точка: API-приложение на **.NET 8 (ASP.NET Core Minimal API + EF Core)**, подключённое к **PostgreSQL 16**, запуск через **Docker Compose**.

Связка: `API (сервис api) -> PostgreSQL (сервис db)`

## Структура проекта

```
tasks-api/
├── src/TasksApi/
│   ├── Program.cs          # API: CRUD endpoints, модель TaskItem, DbContext
│   └── TasksApi.csproj
├── Dockerfile              # сборка образа API (multi-stage: sdk -> aspnet)
├── docker-compose.yml      # сервисы api и db, сеть, volume db_data
├── check.sh                # автоматическая проверка: запуск, CRUD, перезапуск, логи
├── docs/                   # подтверждения: ps, CRUD, сохранение данных, logs
└── README.md
```

## Сущность

`TaskItem` (таблица `tasks`) — задача в сервисе задач:

| Поле          | Тип       | Описание                 |
|---------------|-----------|--------------------------|
| `id`          | int       | первичный ключ (serial)  |
| `title`       | string    | название, обязательно    |
| `description` | string?   | описание                 |
| `isCompleted` | bool      | выполнена ли задача      |
| `createdAt`   | DateTime  | дата создания (UTC)      |

## Endpoints

| Метод  | URL                | Действие               |
|--------|--------------------|------------------------|
| POST   | `/api/tasks`       | Create — создать       |
| GET    | `/api/tasks`       | Read — все задачи      |
| GET    | `/api/tasks/{id}`  | Read — задача по id    |
| PUT    | `/api/tasks/{id}`  | Update — изменить      |
| DELETE | `/api/tasks/{id}`  | Delete — удалить       |

## Конфигурация Docker Compose

| Параметр            | Значение                                   |
|---------------------|--------------------------------------------|
| Образ БД            | `postgres:16`                              |
| Сервис БД           | `db`                                       |
| База / пользователь / пароль | `app` / `postgres` / `1234`       |
| Volume              | `db_data` → `/var/lib/postgresql/data`     |
| Сеть                | `app-network` (bridge)                     |
| Порт API            | `8080`                                     |

Переменные окружения сервиса `api`: `DB_HOST=db`, `DB_PORT=5432`, `DB_NAME=app`, `DB_USER=postgres`, `DB_PASSWORD=1234`.
API собирает из них строку подключения `Host=db;Port=5432;Database=app;...` — то есть подключается к PostgreSQL **по имени сервиса `db`** внутри сети Compose.

`depends_on` с `condition: service_healthy` запускает API только после того, как healthcheck (`pg_isready`) подтвердил готовность PostgreSQL. Дополнительно API при старте повторяет попытки подключения.

## Запуск

Нужен Docker Desktop (или Docker Engine) с Docker Compose.

```bash
docker compose up --build
```

или в фоне:

```bash
docker compose up -d --build
docker compose ps
```

Проверка, что API живой: `curl http://localhost:8080/` → `{"service":"tasks-api","status":"ok"}`

## CRUD-запросы (curl)

> В Windows PowerShell пиши `curl.exe` вместо `curl`. В PowerShell удобнее одинарные кавычки снаружи JSON, как ниже.

```bash
# Create
curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"title":"Сдать контрольную","description":"Docker Compose + PostgreSQL"}'

# Read all
curl http://localhost:8080/api/tasks

# Read by id
curl http://localhost:8080/api/tasks/1

# Update
curl -X PUT http://localhost:8080/api/tasks/1 -H "Content-Type: application/json" -d '{"title":"Сдать контрольную","description":"Готово","isCompleted":true}'

# Delete
curl -X DELETE http://localhost:8080/api/tasks/1 -w "%{http_code}\n"
```

## Проверка сохранения данных после перезапуска

```bash
curl -X POST http://localhost:8080/api/tasks -H "Content-Type: application/json" -d '{"title":"Проверка volume"}'
docker compose down          # контейнеры удаляются, volume db_data остаётся
docker compose up -d
curl http://localhost:8080/api/tasks    # задача на месте
docker compose exec db psql -U postgres -d app -c "SELECT * FROM tasks;"
```

Важно: `docker compose down` **без** флага `-v`. С `-v` volume удалится вместе с данными.

## Логи

```bash
docker compose logs
docker compose logs api
docker compose logs db
```

## Автоматическая проверка

Скрипт `check.sh` (Linux/macOS/Git Bash) делает всё по порядку и сохраняет вывод в `docs/`:

```bash
./check.sh
```

| Файл                        | Что подтверждает                            |
|-----------------------------|---------------------------------------------|
| `docs/compose-ps.txt`       | сервисы api и db запущены                   |
| `docs/crud-check.txt`       | Create, Read, Update, Delete работают       |
| `docs/persistence-check.txt`| данные сохранились после down/up            |
| `docs/compose-logs.txt`     | вывод `docker compose logs`                 |

Чтобы начать с чистой базы: `docker compose down -v`.

## Для защиты (коротко)

- **Сущность:** `TaskItem` — задача; CRUD через `/api/tasks`.
- **Связь с темой:** проектная тема — сервис задач, задача — его основная сущность.
- **Сервисы:** `api` (собирается из Dockerfile) и `db` (`postgres:16`).
- **Почему PostgreSQL:** полноценная СУБД, работает отдельным сервисом/контейнером; SQLite — файл внутри приложения, отдельным сервисом не запускается.
- **Подключение:** по имени сервиса `db` в общей сети `app-network`; Docker DNS резолвит `db` в IP контейнера.
- **Env:** `POSTGRES_DB/USER/PASSWORD` для `db`; `DB_HOST/PORT/NAME/USER/PASSWORD` для `api`.
- **Volume:** `db_data` смонтирован в `/var/lib/postgresql/data`, поэтому данные переживают удаление контейнеров.
- **Проверка:** curl-запросы CRUD, затем `docker compose down` → `up -d` → данные на месте (через API и через `psql`).
