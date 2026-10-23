#!/usr/bin/env bash
# Полная проверка: запуск, CRUD, сохранение данных после перезапуска.
# Вывод сохраняется в docs/*.txt как подтверждение для сдачи.
set -e
cd "$(dirname "$0")"
API=http://localhost:8080/api/tasks
mkdir -p docs

wait_api() {
  for i in $(seq 1 60); do
    curl -s -o /dev/null http://localhost:8080/ && return 0
    sleep 2
  done
  echo "API не поднялся"; exit 1
}

echo "== 1. docker compose up -d --build =="
docker compose up -d --build
wait_api

echo "== 2. docker compose ps =="
docker compose ps | tee docs/compose-ps.txt

{
  echo "### CREATE"
  echo '$ curl -X POST' "$API" "-H 'Content-Type: application/json' -d '{\"title\":\"Сдать контрольную\",\"description\":\"Docker Compose + PostgreSQL\"}'"
  curl -s -X POST "$API" -H 'Content-Type: application/json' \
       -d '{"title":"Сдать контрольную","description":"Docker Compose + PostgreSQL"}'; echo
  echo '$ curl -X POST' "$API" "-H 'Content-Type: application/json' -d '{\"title\":\"Подготовиться к защите\"}'"
  curl -s -X POST "$API" -H 'Content-Type: application/json' \
       -d '{"title":"Подготовиться к защите"}'; echo

  echo; echo "### READ (все)"
  echo "\$ curl $API"
  curl -s "$API"; echo

  echo; echo "### READ (по id)"
  echo "\$ curl $API/1"
  curl -s "$API/1"; echo

  echo; echo "### UPDATE"
  echo '$ curl -X PUT' "$API/1" "-H 'Content-Type: application/json' -d '{\"title\":\"Сдать контрольную\",\"description\":\"Готово\",\"isCompleted\":true}'"
  curl -s -X PUT "$API/1" -H 'Content-Type: application/json' \
       -d '{"title":"Сдать контрольную","description":"Готово","isCompleted":true}'; echo

  echo; echo "### DELETE"
  echo "\$ curl -X DELETE $API/2 -w '%{http_code}'"
  curl -s -X DELETE "$API/2" -w 'HTTP %{http_code}'; echo
  echo "\$ curl $API/2 -w '%{http_code}'"
  curl -s "$API/2" -o /dev/null -w 'HTTP %{http_code}'; echo

  echo; echo "### Итоговое состояние"
  curl -s "$API"; echo
} | tee docs/crud-check.txt

{
  echo "### Данные до перезапуска"
  curl -s "$API"; echo
  echo
  echo "\$ docker compose down"
  docker compose down 2>&1
  echo
  echo "\$ docker compose up -d"
  docker compose up -d 2>&1
} | tee docs/persistence-check.txt
wait_api
{
  echo
  echo "\$ docker compose ps"
  docker compose ps
  echo
  echo "### Данные после перезапуска (volume db_data)"
  echo "\$ curl $API"
  curl -s "$API"; echo
  echo
  echo "### Проверка напрямую в PostgreSQL"
  echo "\$ docker compose exec db psql -U postgres -d app -c 'SELECT * FROM tasks;'"
  docker compose exec -T db psql -U postgres -d app -c 'SELECT * FROM tasks;'
  echo "\$ docker volume ls"
  docker volume ls
} | tee -a docs/persistence-check.txt

echo "== docker compose logs =="
docker compose logs --no-color > docs/compose-logs.txt
tail -n 30 docs/compose-logs.txt
