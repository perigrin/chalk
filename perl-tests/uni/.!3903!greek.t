#!./perl -w

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all("encoding.pm is no longer supported by the perl core");
}

plan tests => 72;

no warnings 'deprecated';
use encoding "greek"; # iso 8859-7

# U+0391, \xC1, \301, GREEK CAPITAL LETTER ALPHA
# U+03B1, \xE1, \341, GREEK SMALL LETTER ALPHA

ok("\xC1"    =~ /\xC1/,     '\xC1 to /\xC1/');
ok("\x{391}" =~ /\xC1/,     '\x{391} to /\xC1/');
ok("\xC1"    =~ /\x{C1}/,   '\xC1 to /\x{C1}/');
ok("\x{391}" =~ /\x{C1}/,   '\x{391} to /\x{C1}/');
ok("\xC1"    =~ /\301/,     '\xC1 to /\301/');
ok("\x{391}" =~ /\301/,     '\x{391} to /\301/');
ok("\xC1"    =~ /\x{391}/,  '\xC1 to /\x{391}/');
ok("\x{391}" =~ /\x{391}/,  '\x{391} to /\x{391}/');

ok("\xC1"    =~ /\xC1/i,    '\xC1 to /\xC1/i');
ok("\xE1"    =~ /\xC1/i,    '\xE1 to /\xC1/i');
ok("\xC1"    =~ /\xE1/i,    '\xC1 to /\xE1/i');
ok("\xE1"    =~ /\xE1/i,    '\xE1 to /\xE1/i');
ok("\xC1"    =~ /\x{391}/i, '\xC1 to /\x{391}/i');
ok("\xE1"    =~ /\x{391}/i, '\xE1 to /\x{391}/i');
ok("\xC1"    =~ /\x{3B1}/i, '\xC1 to /\x{3B1}/i');
ok("\xE1"    =~ /\x{3B1}/i, '\xE1 to /\x{3B1}/i');

ok("\xC1"    =~ /[\xC1]/,     '\xC1 to /[\xC1]/');
ok("\x{391}" =~ /[\xC1]/,     '\x{391} to /[\xC1]/');
ok("\xC1"    =~ /[\x{C1}]/,   '\xC1 to /[\x{C1}]/');
ok("\x{391}" =~ /[\x{C1}]/,   '\x{391} to /[\x{C1}]/');
ok("\xC1"    =~ /[\301]/,     '\xC1 to /[\301]/');
ok("\x{391}" =~ /[\301]/,     '\x{391} to /[\301]/');
ok("\xC1"    =~ /[\x{391}]/,  '\xC1 to /[\x{391}]/');
ok("\x{391}" =~ /[\x{391}]/,  '\x{391} to /[\x{391}]/');

ok("\xC1"    =~ /[\xC1]/i,    '\xC1 to /[\xC1]/i');
ok("\xE1"    =~ /[\xC1]/i,    '\xE1 to /[\xC1]/i');
ok("\xC1"    =~ /[\xE1]/i,    '\xC1 to /[\xE1]/i');
ok("\xE1"    =~ /[\xE1]/i,    '\xE1 to /[\xE1]/i');
ok("\xC1"    =~ /[\x{391}]/i, '\xC1 to /[\x{391}]/i');
ok("\xE1"    =~ /[\x{391}]/i, '\xE1 to /[\x{391}]/i');
ok("\xC1"    =~ /[\x{3B1}]/i, '\xC1 to /[\x{3B1}]/i');
ok("\xE1"    =~ /[\x{3B1}]/i, '\xE1 to /[\x{3B1}]/i');

ok("\xC1"    =~ '\xC1',       '\xC1 to \'\xC1\'');
ok("\xC1"    =~ '\x{C1}',     '\xC1 to \'\x{C1}\'');
ok("\xC1"    =~ '\301',       '\xC1 to \'\301\'');
ok("\xC1"    =~ '\x{391}',    '\xC1 to \'\x{391}\'');
ok("\xC1"    =~ '[\xC1]',     '\xC1 to \'[\xC1]\'');
ok("\xC1"    =~ '[\x{C1}]',   '\xC1 to \'[\x{C1}]\'');
ok("\xC1"    =~ '[\301]',     '\xC1 to \'[\301]\'');
ok("\xC1"    =~ '[\x{391}]',  '\xC1 to \'[\x{391}]\'');

