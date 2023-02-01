#
# Copyright (c) 2016 Yuriy Sydor <yuriysydor1991@gmail.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

#!/bin/bash

# версія поточного скрипта
VERSION="1.0.0"

# змінні, які містять інформацію про підключення до локальної бази MySQL
mysql_db_name=
mysql_db_username=
mysql_db_password=

# директорія в якій буде міститись кінцевий файл бекапу
backup_dest_dir=
# тип файлу архіву
backup_archive_type=
# тип файлу по замовчуванню
default_archive_type="gz"
# файл журналу дій скрипта
backup_log_file=
# кінцева назва файлу бекапу
backup_name=
# директорія розміщення скриптів сайту
site_dir=

#тимчасова директорія в яку будуть акумулюватись файли бекапу
tmp_dir=

# доступні типи архіву
declare -A avail_archive_types
avail_archive_types["tar"]="cf"
avail_archive_types["gz"]="czf"
avail_archive_types["bz2"]="cjf"
avail_archive_types["xz"]="cJf"

# функція, яка виводить документацію по програмі і його версію
print_usage_and_exit ()
{
  echo -e "$0 v.$VERSION"
  echo -e "Program, that helps to create Web-site backups\n"
  echo -e "Usage:"
  echo -e "\n\t$0 [OPTIONS]"
  echo -e "\nWhere OPTIONS can be following:"
  echo -e "\n\t--dest-backup-dir[=]DIR "
  echo -e "\t\tSave backup file to destination directory DIR."
  echo -e "\t\tIf no directory specified - backup to home directory"
  echo -e "\n\t--db-info-mysql[=]DBINFO"
  echo -e "\t\tAdd to backup specified database dump from local MySQL server"
  echo -e "\t\tDBINFO must to have next syntax: DBNAME:DBUSER:DBPASSWORD"
  echo -e "\t\tWhere:"
  echo -e "\t\tDBNAME - MySQL local server database name needed to backup;"
  echo -e "\t\tDBUSER - MySQL local server database valid username;"
  echo -e "\t\tDBPASSWORD - MySQL local server username password."
  echo -e "\n\t--site-dir[=]DIR "
  echo -e "\t\tAdd to backup archive site source directory from directory DIR"
  echo -e "\n\t--archive-type[=]TYPE" 
  echo -e "\t\tBackup archive will be of type TYPE."
  echo -e "\t\tAvailable next archives types "
  echo -e "\t\t(if program tar installed on your host): "${!avail_archive_types[@]}"."
  echo -e "\n\t--backup-name[=]FILENAME"
  echo -e "\t\tdest backup filename will be FILENAME.TYPE"
  echo -e "\n\t--log[=]LOGFILE"
  echo -e "\t\tLog backuping process to log file LOGFILE.\n\t\tIf no log file specified - output all message to stdout"
  echo -e "\n Permission to use, copy, modify, and distribute this software for any"
  echo -e " purpose with or without fee is hereby granted, provided that the above"
  echo -e " copyright notice and this permission notice appear in all copies.\n"
  echo -e " THE SOFTWARE IS PROVIDED \"AS IS\" AND THE AUTHOR DISCLAIMS ALL WARRANTIES"
  echo -e " WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF"
  echo -e " MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR"
  echo -e " ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES"
  echo -e " WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN"
  echo -e " ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF"
  echo -e " OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE."
  echo -e "\n Copyright (c) 2016 Yuriy Sydor <yuriysydor1991@gmail.com>"
  
  exit 0 ;
}

# перевіряємо кількість переданих параметрів
if [[ $# -le 1 ]] ; then
  print_usage_and_exit
fi

# функція, яка при наявності вказаного файлу журналу, 
# записує повідомлення у нього, в іншому випадку
# виводить передані параметри на екран
log_message ()
{
  local form_msg=$(date +"%d.%m.%Y %H:%M:%S ")$*
  
  # якщо вказаний файл - робимо запис у нього
  # в іншому випадку виводимо запис в стандартний вивід
  if [[ -n $backup_log_file ]]
  then
    echo "$form_msg" >> "$backup_log_file"
  else
    echo "$form_msg"
  fi ;
}

# функція яка створює дамп локальної MySQL бази в поточну директорію
# перший параметр - назва бази даних
# другий - ім'я користувача, який має необхідні права 
# на використання бази (LOCK TABLES, SELECT і інші)
# третій параметр - пароль до вказаного користувача бази даних
# четвертий параметр - назва файлу дампу бази
make_mysql_dump ()
{
  if [[ -z $1 || -z $2 || -z $3 ]] ; then
    log_message "make_mysql_dump(): some connection data is not available - can\`t create dump"
    return 1
  fi
  
  dump_name=$4
  
  if [[ -z $dump_name ]] ; then
    dump_name="mysql_database_dump"
  fi
  
  # перевіряємо чи файл має закінчення ".sql"
  if [[ ! $dump_name = "*.sql" ]] ; then
    # якщо закінчення не існує - додаємо його
    dump_name="$dump_name".sql
  fi
  
  log_message "make_mysql_dump(): Trying to create MySQL database dump to file $dump_name"
  
  if [[ ! $(mysqldump --user="$2" --password="$3" --result-file="$dump_name" "$1") ]]
  then
    log_message "make_mysql_dump(): Fail to create database dump!!!"
    return 2
  fi
  
  log_message "make_mysql_dump(): Done to creating database dump"
}

# цикл розпізнавання переданих параметрів
for (( iter=$((1)) ; $iter<=$# ; ++iter ))
do
  
  # отримуємо позиційний параметр скрипта за номером iter
  param=${@:$iter:1}
  next_param=${@:$(($iter+1)):1}
  
  # перевіряємо, чи наступний параметр не подібний на прапорець
  if [[ $next_param = -* ]] ; then
    # якщо так - робимо змінну пустою
    next_param=
  fi
  
  # інтерпретуємо параметр який міститься в $param
  # не використовуємо вбудовану команду getopts,
  # оскільки вона не підтримує довгі прапорці
  case $param in
  
    --backup-name* | -backup-name*)
      
      #на випадок вказування даних після знаку "="
      if [[ "$param" = *=* ]] ; then
        backup_name=${param#*=}
      # на випадок вказування даних в якості окремого параметра
      elif [[ -n $next_param ]] ; then
        backup_name=$next_param
        # інкрементуємо ітератор поза охороною циклу
        # щоб цикл не сприймав дані прапорця в якості
        # іншого прапорця
        iter=$iter+1
      else
        echo -e "parameter must to have data: '$param'\n"
        print_usage_and_exit
      fi
      
      # замінюємо спеціальні символи в назві бекапу
      backup_name=$(date +"$backup_name")
    
      ;;
  
    --db-info-mysql* | -db-info-mysql*)
      
      #на випадок вказування даних після знаку "="
      if [[ "$param" = *=* ]] ; then
        mysql_db_name=${param#*=}
      # на випадок вказування даних в якості окремого параметра
      elif [[ -n $next_param ]] ; then
        mysql_db_name=$next_param
        # інкрементуємо ітератор поза охороною циклу
        # щоб цикл не сприймав дані прапорця в якості
        # іншого прапорця
        iter=$iter+1
      else
        echo -e "parameter must to have data: '$param'\n"
        print_usage_and_exit
      fi
      
      # отримуємо значення параметрів підключення до MySQL,
      # поступово видаляючи частини переданого рядка
      
      # видаляємо початок і кінець параметра для ім'я користувача 
      mysql_db_username=${mysql_db_name#*:}
      mysql_db_username=${mysql_db_username%:*}
      
      # видаляємо початок параметру з двома символами ":"
      # щоб отримати пароль з кінця
      mysql_db_password=${mysql_db_name##*:}
      
      # отримуємо ім'я бази даних, 
      # видаляючи кінець рядка з двома символами ":"
      mysql_db_name=${mysql_db_name%%:*}
      
      ;;
      
    --archive-type* | -archive-type*)
      
      #на випадок вказування шляху після знаку "="
      if [[ "$param" = *=* ]] ; then
        backup_archive_type=${param#*=}
      # на випадок вказування шляху в якості окремого параметра
      elif [[ -n $next_param ]] ; then
        backup_archive_type=$next_param
        # інкрементуємо ітератор поза охороною циклу
        # щоб цикл не сприймав дані прапорця в якості
        # іншого прапорця
        iter=$iter+1
      else
        echo -e "parameter must to have data: '$param'\n"
        print_usage_and_exit 
      fi
    
      ;;
  
    --site-dir* | -site-dir*)
      
      #на випадок вказування шляху після знаку "="
      if [[ "$param" = *=* ]] ; then
        site_dir=${param#*=}
      # на випадок вказування шляху в якості окремого параметра
      elif [[ -n $next_param ]] ; then
        site_dir=$next_param
        # інкрементуємо ітератор поза охороною циклу
        # щоб цикл не сприймав дані прапорця в якості
        # іншого прапорця
        iter=$iter+1
      else
        echo -e "parameter must to have data: '$param'\n"
        print_usage_and_exit 
      fi
      
      # робимо шлях до журналу канонічним на випадок
      # зміни поточної директорії командою cd
      site_dir=$(readlink -f $site_dir)
      
      ;;
      
    --dest-backup-dir* | -dest-backup-dir*)
    
      #на випадок вказування шляху після знаку "="
      if [[ "$param" = *=* ]] ; then
        backup_dest_dir=${param#*=}
      # на випадок вказування шляху в якості окремого параметра
      elif [[ -n $next_param ]] ; then
        backup_dest_dir=$next_param
        # інкрементуємо ітератор поза охороною циклу
        # щоб цикл не сприймав дані прапорця в якості
        # іншого прапорця
        iter=$iter+1
      else
        echo -e "parameter must to have data: '$param'\n"
        print_usage_and_exit 
      fi
      
      # робимо шлях до журналу канонічним на випадок
      # зміни поточної директорії командою cd
      backup_dest_dir="$(readlink -f $backup_dest_dir)"
      
      ;;
  
    --log* | -log*)
    
      # якщо шлях до журналу стоїть після знаку "="
      if [[ "$param" = *=* ]] ; then
        backup_log_file=${param#*=}
      # якщо шлях журналу являється наступним параметром
      elif [[ -n $next_param ]] ; then 
        backup_log_file=$next_param
        # інкрементуємо ітератор поза охороною циклу
        # щоб цикл не сприймав дані прапорця в якості
        # іншого прапорця
        iter=$iter+1 
      else
        echo -e "parameter must to have data: '$param'\n"
        print_usage_and_exit 
      fi
      
      # робимо шлях до журналу канонічним на випадок
      # зміни поточної директорії командою cd
      backup_log_file="$(readlink -f $backup_log_file)"
      
      ;;
      
    *)
      # "зловили" невідомий параметр - виводимо
      # документацію про використання програми
      # і завершуємо роботу
      echo -e "Unknown parameter: $param)\n"
      print_usage_and_exit 
      
      ;;
      
  esac
  
done

log_message "Start to creating backup of: $site_dir"

if [[ -z $mysql_db_name && -z $site_dir ]] ; then
  log_message "Directory or MySQL connection info must be supplied. Nothing to backup. Quiting!"
  exit 1
fi

# якщо не встановлене значення директорії
# розміщення файлу - встановлюємо її в домашню
# поточного користувача, який викликав скрипт
if [[ -z $backup_dest_dir ]] ; then
  backup_dest_dir=$(readlink -f ~)
  log_message "Didn\`t find --dest-backup-dir parameter, makeing it home: $backup_dest_dir"
fi

# визначаємо шлях для тимчасової папки бекапу
tmp_dir="$backup_dest_dir"/"$backup_name"

# на всякий випадок, перевіряємо чи tmp_dir не вказує на 
# кореневий каталог файлової системи, якщо так - вихід з скрипта, 
# оскільки директорія буде видалятися в майбутньому
if [[ $tmp_dir = "/" ]]; then
  log_message "Something realy bad happens: temporary directory points to $tmp_dir"
  log_message "QUIT!!!"
  exit 1
fi

# якщо тимчасова папка вже існує - видаляємо її
log_message "Checking if $tmp_dir already exists"
if [[ -d "$tmp_dir" ]] ; then
  log_message "Directory $tmp_dir already exists - erasing it"
  rm -fr "$tmp_dir"
fi

# спроба створити тимчасовий каталог
log_message "Trying to create temporary dir: $tmp_dir"
if [[ ! $(mkdir -v "$tmp_dir") ]] ; then
  log_message "Fail to create temporary directory: $tmp_dir"
  exit 2
fi

# змінні які індикують успішність створення бекапу бази
# і копіювання файлів скриптів
success_db_dump=
success_scripts_copy=

# якщо вказана назва бази даних MySQL - створюємо її дамп
if [[ -n "$mysql_db_name" ]] ; then
  log_message "Trying to create MySQL database dump"
  if [[ $(make_mysql_dump "$mysql_db_name" "$mysql_db_username" "$mysql_db_password" "${tmp_dir}/${backup_name}_mysql_dump") ]]
  then
    success_db_dump="Success"
  fi
else
  # якщо не вказана база даних - заповнюємо змінну індикатор
  success_db_dump="Not supplied"
  log_message "Database connection info doesn't supplied - skipping database dump"
fi

# якщо вказана директорія розміщення сайту -
# копіюємо її до тимчасової директорії розміщення даних бекапу
if [[ -n "$site_dir" ]] ; then
  log_message "Copying site scripts folder '$site_dir' to temporary directory"
  if ! $(cp -R "$site_dir" "$tmp_dir") ; then
    log_message "Fail to copy site folder script from path: $site_dir"
  else
    success_scripts_copy="Success"
  fi
else
  # якщо не вказана база даних - заповнюємо змінну індикатор
  success_scripts_copy="Not supplied"
  log_message "Scripts folder doesn't supplied - skipping backuping site scipts"
fi

# перевіряємо чи хоча б одна операція виконалась успішно
# якщо дві змінні-індикатори пусті - вихід з скрипта
if [[ -z $success_db_dump && -z $success_scripts_copy ]]
then
  log_message "Fail to create mysql dump and copy site scripts!!!"
  rm -fr "${tmp_dir}"
  exit 3
fi

# переміщуємось в папку призначення файлу
cd $backup_dest_dir

# перевіряємо параметри, які передаються команді tar
# якщо пусті - передаємо параметри для стандартного типу архіву
tar_opts=${avail_archive_types["${backup_archive_type}"]}
file_ext=tar."${backup_archive_type}"
if [[ -z $tar_opts ]] ; then
  tar_opts=${avail_archive_types[$default_archive_type]}
  file_ext=tar."${default_archive_type}"
fi

# якщо розширення "tar" вказано два рази
file_ext=${file_ext/tar.tar/tar}

# якщо успішно виконано хоча б одна операція - архівуємо тимчасову директорію
log_message "Trying to create backup files archive: ${backup_dest_dir}/${backup_name}.${file_ext}"
if ! $(tar "${tar_opts}" "$backup_name"."${file_ext}" "${backup_name}")
then
  log_message "Error while creating backup archive!!!"
  rm -fr "${tmp_dir}"
  exit 4
fi

log_message "Trying to erase temporary backup directory: $tmp_dir"
if ! $(rm -fr "$tmp_dir") ; then
  log_message "Fail to erase temporary directory"
fi

log_message "End"

exit 0

