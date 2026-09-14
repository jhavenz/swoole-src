#!/usr/bin/env bash
#
# Builds this branch of Swoole against Homebrew's PHP 8.6 on macOS and enables it.
#
# PHP 8.6 comes from shivammathur/php (keg-only, so the linked `php` is left alone).
# Swoole upstream does not support 8.6 yet; this branch carries the 8.6 compatibility work plus the
# zend_fcall_info.consumed_args fix for callbacks run as coroutines.
#
# Usage: tools/php86-homebrew.sh            build, install and enable
#        tools/php86-homebrew.sh --check    only print what is installed

set -euo pipefail

formula="shivammathur/php/php@8.6"
src="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v brew >/dev/null; then
    echo "Homebrew is required." >&2
    exit 1
fi

prefix="$(brew --prefix php@8.6 2>/dev/null || true)"

if [[ "${1:-}" == "--check" ]]; then
    if [[ -z "$prefix" || ! -x "$prefix/bin/php" ]]; then
        echo "PHP 8.6 is not installed: brew install $formula"
        exit 1
    fi
    "$prefix/bin/php" -r 'echo "PHP ", PHP_VERSION, " · swoole ", phpversion("swoole") ?: "not loaded", " · openswoole ", extension_loaded("openswoole") ? "loaded" : "absent", "\n";'
    exit 0
fi

if [[ -z "$prefix" || ! -x "$prefix/bin/php" ]]; then
    brew install "$formula"
    prefix="$(brew --prefix php@8.6)"
fi

brew install pcre2 openssl@3 brotli libpq

pcre2="$(brew --prefix pcre2)"
openssl="$(brew --prefix openssl@3)"
brotli="$(brew --prefix brotli)"
libpq="$(brew --prefix libpq)"

cd "$src"

# A shell that exports CPPFLAGS for another PHP (commonly Homebrew's default php) would pull in the
# wrong headers, so the build sets its own.
export CPPFLAGS="-I$pcre2/include -I$openssl/include -I$brotli/include -I$libpq/include"
export LDFLAGS="-L$pcre2/lib -L$openssl/lib -L$libpq/lib"
export LIBPQ_CFLAGS="-I$libpq/include"
export LIBPQ_LIBS="-L$libpq/lib -lpq"

"$prefix/bin/phpize" --clean >/dev/null 2>&1 || true
"$prefix/bin/phpize"
./configure \
    --with-php-config="$prefix/bin/php-config" \
    --with-openssl-dir="$openssl" \
    --enable-sockets \
    --enable-mysqlnd \
    --enable-swoole-curl \
    --enable-swoole-pgsql \
    --enable-swoole-sqlite
make -j"$(sysctl -n hw.ncpu)"
make install

scan_dir="$("$prefix/bin/php" -r 'echo PHP_CONFIG_FILE_SCAN_DIR;')"
mkdir -p "$scan_dir"
printf 'extension=swoole.so\n' > "$scan_dir/ext-swoole.ini"

"$0" --check
