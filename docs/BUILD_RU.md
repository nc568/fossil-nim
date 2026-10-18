# Руководство по сборке

## Требования

- Nim 2.0+
- clang или gcc (для обычной сборки)
- cproc + QBE (для QBE сборки)
- libsqlite3-dev, zlib, libssl-dev
- Опционально: libmdbx-dev, liblmdb-dev

## Обычная сборка

```bash
nimble build
# или
make build
```

Бинари в `bin/fossil` и `bin/fossil-mcp`.

## Сборка QBE

```bash
# Генерация C файлов
nimble buildQbe
# или
make build-qbe-c

# Компиляция cproc
make qbe

# Проверка
./bin/fossil-qbe version
```

## Вендорная сборка (без системных зависимостей)

```bash
# Поместите sqlite3.c и mdbx.c в cinterop/
# Затем
nim c -d:vendored -d:release src/fossil/cli/main.nim
```

## Docker

```dockerfile
FROM nimlang/nim:2.0.0-alpine as builder
RUN apk add sqlite-dev zlib-dev openssl-dev
COPY . /src
WORKDIR /src
RUN nimble build

FROM alpine
COPY --from=builder /src/bin/fossil /usr/local/bin/
ENTRYPOINT ["fossil"]
```

## Кросс-компиляция

Nim поддерживает кросс через `--os:any` и кастомный cc.

Для QBE, сам QBE поддерживает x86_64, aarch64, riscv64.

## Устранение неполадок

- `sqlite3.h not found`: установите libsqlite3-dev или используйте `-d:vendored`
- `mdbx.h not found`: установите libmdbx или используйте только sqlite бэкенд
- `cproc: command not found`: установите cproc с https://git.sr.ht/~mcf/cproc
- Проблемы с кэшем Nim: `rm -rf nimcache build/cgen`
