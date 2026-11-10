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

get_id() { sed -E 's/.*"id":([0-9]+).*/\1/'; }

{
  echo "### CREATE"
  echo '$ curl -X POST' "$API" "-H 'Content-Type: application/json' -d '{\"title\":\"Сдать контрольную\",\"description\":\"Docker Compose + PostgreSQL\"}'"
  R1=$(curl -s -X POST "$API" -H 'Content-Type: application/json' \
       -d '{"title":"Сдать контрольную","description":"Docker Compose + PostgreSQL"}')
  echo "$R1"; ID1=$(echo "$R1" | get_id)
  echo '$ curl -X POST' "$API" "-H 'Content-Type: application/json' -d '{\"title\":\"Подготовиться к защите\"}'"
  R2=$(curl -s -X POST "$API" -H 'Content-Type: application/json' \
       -d '{"title":"Подготовиться к защите"}')
  echo "$R2"; ID2=$(echo "$R2" | get_id)

  echo; echo "### READ (все)"
  echo "\$ curl $API"
  curl -s "$API"; echo

  echo; echo "### READ (по id)"
  echo "\$ curl $API/$ID1"
  curl -s "$API/$ID1"; echo

  echo; echo "### UPDATE"
  echo '$ curl -X PUT' "$API/$ID1" "-H 'Content-Type: application/json' -d '{\"title\":\"Сдать контрольную\",\"description\":\"Готово\",\"isCompleted\":true}'"
  curl -s -X PUT "$API/$ID1" -H 'Content-Type: application/json' \
       -d '{"title":"Сдать контрольную","description":"Готово","isCompleted":true}'; echo

  echo; echo "### DELETE"
  echo "\$ curl -X DELETE $API/$ID2 -w '%{http_code}'"
  curl -s -X DELETE "$API/$ID2" -w 'HTTP %{http_code}'; echo
  echo "\$ curl $API/$ID2 -w '%{http_code}'"
  curl -s "$API/$ID2" -o /dev/null -w 'HTTP %{http_code}'; echo

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
