#!./perl -w

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all("encoding.pm is no longer supported by the perl core");
}

plan tests => 94;

no warnings 'deprecated';
use encoding "latin2"; # iso 8859-2

# U+00C1, \xC1, \301, LATIN CAPITAL LETTER A WITH ACUTE
# U+0102, \xC3, \402, LATIN CAPITAL LETTER A WITH BREVE
# U+00E1, \xE1, \303, LATIN SMALL LETTER A WITH ACUTE
# U+0103, \xE3, \403, LATIN SMALL LETTER A WITH BREVE

ok("\xC1"    =~ /\xC1/,     '\xC1 to /\xC1/');
ok("\x{C1}"  =~ /\x{C1}/,   '\x{C1} to /\x{C1}/');
ok("\xC3"    =~ /\xC3/,     '\xC3 to /\xC3/');
ok("\x{102}" =~ /\xC3/,     '\x{102} to /\xC3/');
ok("\xC3"    =~ /\x{C3}/,   '\xC3 to /\x{C3}/');
ok("\x{102}" =~ /\x{C3}/,   '\x{102} to /\x{C3}/');
ok("\xC3"    =~ /\x{102}/,  '\xC3 to /\x{102}/');
ok("\x{102}" =~ /\x{102}/,  '\x{102} to /\x{102}/');

ok("\xC1"    =~ /\xC1/i,    '\xC1 to /\xC1/i');
ok("\xE1"    =~ /\xC1/i,    '\xE1 to /\xC1/i');
ok("\xC1"    =~ /\xE1/i,    '\xC1 to /\xE1/i');
ok("\xE1"    =~ /\xE1/i,    '\xE1 to /\xE1/i');
ok("\x{102}" =~ /\xC3/i,    '\x{102} to /\xC3/i');
ok("\x{103}" =~ /\xC3/i,    '\x{103} to /\xC3/i');
ok("\x{102}" =~ /\xE3/i,    '\x{102} to /\xE3/i');
ok("\x{103}" =~ /\xE3/i,    '\x{103} to /\xE3/i');

ok("\xC1"    =~ /[\xC1]/,     '\xC1 to /[\xC1]/');
ok("\x{C1}"  =~ /[\x{C1}]/,   '\x{C1} to /[\x{C1}]/');
ok("\xC3"    =~ /[\xC3]/,     '\xC3 to /[\xC3]/');
ok("\x{102}" =~ /[\xC3]/,     '\x{102} to /[\xC3]/');
ok("\xC3"    =~ /[\x{C3}]/,   '\xC3 to /[\x{C3}]/');
ok("\x{102}" =~ /[\x{C3}]/,   '\x{102} to /[\x{C3}]/');
ok("\xC3"    =~ /[\x{102}]/,  '\xC3 to /[\x{102}]/');
ok("\x{102}" =~ /[\x{102}]/,  '\x{102} to /[\x{102}]/');

ok("\xC1"    =~ /[\xC1]/i,  '\xC1 to /[\xC1]/i');
ok("\xE1"    =~ /[\xC1]/i,  '\xE1 to /[\xC1]/i');
ok("\xC1"    =~ /[\xE1]/i,  '\xC1 to /[\xE1]/i');
ok("\xE1"    =~ /[\xE1]/i,  '\xE1 to /[\xE1]/i');
ok("\x{102}" =~ /[\xC3]/i,  '\x{102} to /[\xC3]/i');
ok("\x{103}" =~ /[\xC3]/i,  '\x{103} to /[\xC3]/i');
ok("\x{102}" =~ /[\xE3]/i,  '\x{102} to /[\xE3]/i');
ok("\x{103}" =~ /[\xE3]/i,  '\x{103} to /[\xE3]/i');

ok("\xC1"    =~ '\xC1',       '\xC1 to \'\xC1\'');
ok("\xC1"    =~ '\x{C1}',     '\xC1 to \'\x{C1}\'');
ok("\xC3"    =~ '\303',       '\xC3 to \'\303\'');
ok("\xC3"    =~ '\x{102}',    '\xC3 to \'\x{102}\'');
ok("\xC1"    =~ '[\xC1]',     '\xC1 to \'[\xC1]\'');
ok("\xC1"    =~ '[\x{C1}]',   '\xC1 to \'[\x{C1}]\'');
ok("\xC3"    =~ '[\303]',     '\xC3 to \'[\303]\'');
ok("\xC3"    =~ '[\x{102}]',  '\xC3 to \'[\x{102}]\'');

