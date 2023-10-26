# Rationale Behind Bash Scripting

==TBD

Используйте shellcheck
Будет легче поддерживать скрипты. На каждое предупреждение на сайте shellcheck есть страница пояснений.
Используйте Шебанг
Всегда указывайте интерпретатор, который будет исполнять скрипт, в первой строчке скрипта:
#!/bin/sh
или
#!/bin/bash
Не используйте новую функциональность
Если ваш скрипт требует использования новой функциональности bash, например, по соображениям скорости и работы с данными в памяти, то скорее всего его следует написать на python3.
1. Вместо [[ используйте test.
2. Хэш-таблица - файл с именем ключа.
3. Список - файл. Для большинства операций написаны готовые программы, например, чтобы получить все элементы list1, которые на содержатся в list2:
$ sort list1 list2 list2 | uniq -u
В некоторых установках Линукса, в том числе в новом Дебиан, /bin/sh указывает на dash вместо bash. У этого интерпретатора меньше возможностей. Например. поддерживаются {}, local a=b, export a=b.
Можно использовать синтаксис, который работает как в bash, так и в dash:
1. Вместо
$ function f() {
  echo Function
}
пишите
$ f() {
  echo Function
}
Используйте останов по ошибке
В отличие от обычных программ скрипты после ошибки не останавливаются и могут поломать что-нибудь ещё.  Установите следующую опцию в начале работы, чтобы скрипт останавливался по ошибке:
$ set -e
Также для отладки полезно включать:
$ set -vx
При использовании пайпов используйте для корректной обработки ошибок:
$ set -o pipefail
Для того, чтобы ваш скрипт убивал свои подпроцессы используйте:
$ shopt -s huponexit
Если вы внимательно читали этот раздел, то знаете, что в шелле есть три разных синтаксиса для установки разных внутренних опций. Но главное здесь - не опции, а методологическое правило "сломайся быстро". Вместо сложной логики в любой непонятной ситуации скрипт должен выполнить простую проверку и остановиться с ошибкой.
Используйте кавычки вокруг аргументов
При наличии пробела в имени файла следующая команда будет интерпретирована неправильно.
$ cp $file $target
 Правильный вариант:
$ cp "$file" "$target"
Другой пример:
$ cp *.txt /dir
Если в имени какого-то из txt-файлов - пробел, он не будет скопирован. Правильный вариант:
$ cp "*.txt" /dir
Не используйте файлы с именем, начинающимся с -
Такие файлы не надо создавать самому. Но если файлы приходят откуда-то снаружи, потребуется добавить в скрипт -- перед передачей их в качестве аргументов системным командам.
2. Вместо
$ local a="$b"
пишите
$ local a
$ a="$b"
3. Вместо
$ export a="$b"
пишите
$ a="$b"
$ export a
По возможности лучше не использовать экспорт переменных.
Также, существуют ситуации, когда нестандартный синтаксис не выдает ошибку, но дает разный результат, например:
$ f() {
‍‍‍‍‍‍ ‍‍echo $a
}
$ a=0
$ a=1 f
$ echo $a
Используйте IFS= read -r
Опция -r позволит читать бэкслэши \. Очистка IFS гарантирует, что будет прочитана ровно одна строка.
Используйте функции do_something
Использование имен функций, начинающихся с глагола, поможет не писать комментарии # here we do something, а также эффективно отлаживать код по частям. Вместо того, чтобы описывать в комментариях аргументы функций, используйте значимые имена переменных:
backup_package() {
  local package
  package="$1"

  cp "$package" "$package".old
}
Используйте trap для очистки состояния
Следующая команда гарантирует, что cleanup будет вызван при любом завершении скрипта, за исключением сигнала -KILL.
$ trap cleanup EXIT
Можно, например, отмонтировать временные пути.
Пишите компактно
Мало строк - проще читать. Например, HEREDOC:
$ cat <<EOF >autogen.sh
echo This is autogenerated $SCRIPT
EOF
Используйте || вместо if, не используйте &&:
$ do_action || report_error
Используйте { вместо (
Группа команд в фигурных скобках выполняется без запуска дополнительного процесса.
Удаляйте с возвратом
Вместо удаления можно переместить файл командой mv в папку trash/. Запускать чистку этой папки можно перед началом работы, при этом несколько явно указанных символов в названии папки гарантирует, что не будет стерто что-то полезное:
$ rm -rf trash/
