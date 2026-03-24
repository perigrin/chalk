# ABOUTME: Integration tests for C-backed Boolean semiring with Earley parser.
# ABOUTME: All Boolean loading happens in subprocesses via stub .pm to avoid class registration issues.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use Cwd qw(abs_path);
use Config;

my $so_ext = $Config{dlext};

# Locate repo root relative to this test file
my $repo_root = abs_path(dirname(__FILE__) . '/../..');
my $chalk_so  = "$repo_root/.build/chalk-so/chalk.$so_ext";
my $bool_so   = "$repo_root/.build/chalk-so/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext";
my $perl      = $^X;

plan skip_all => "chalk.so not built (run script/build-chalk-so first)"
    unless -f $chalk_so && -f $bool_so;

# Build a minimal blib layout so Boolean can be loaded via require + stub .pm.
# The BOOT block in Boolean.xs calls Perl_class_setup_stash which requires
# a proper Perl compilation context (PL_compcv must be set). This context
# is only available when a .pm is being require'd — direct _bootstrap() calls
# crash with SIGSEGV because PL_compcv is NULL outside of compilation.
my $tmpdir = tempdir(CLEANUP => 1);
my $blib_arch = "$tmpdir/blib/arch/auto/Chalk/Bootstrap/Semiring/Boolean";
my $blib_lib  = "$tmpdir/blib/lib/Chalk/Bootstrap/Semiring";
make_path($blib_arch);
make_path($blib_lib);

# Copy the pre-built Boolean.so into blib
copy($bool_so, "$blib_arch/Boolean.$so_ext")
    or die "copy Boolean.so failed: $!";

# Write a stub .pm that loads Boolean.so via dl_install_xsub.
# This avoids using DynaLoader::bootstrap_inherit (which adds DynaLoader to @ISA
# and would prevent class_setup_stash from running correctly).
my $stub_pm = "$blib_lib/Boolean.pm";
open my $sfh, '>', $stub_pm or die "Cannot write $stub_pm: $!";
print $sfh <<"END_PM";
package Chalk::Bootstrap::Semiring::Boolean;
use strict;
use warnings;
require DynaLoader;

my \$so;
for my \$dir (\@INC) {
    next if ref \$dir;
    my \$path = "\$dir/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext";
    if (-f \$path) { \$so = \$path; last; }
}
die "Cannot locate Boolean.$so_ext in \@INC" unless defined \$so;

my \$libref = DynaLoader::dl_load_file(\$so, 0)
    or die "dl_load_file: " . DynaLoader::dl_error();
my \$boot = DynaLoader::dl_find_symbol(\$libref, "boot_Chalk__Bootstrap__Semiring__Boolean")
    or die "dl_find_symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub("Chalk::Bootstrap::Semiring::Boolean::_bootstrap", \$boot, \$so);
Chalk::Bootstrap::Semiring::Boolean->_bootstrap();

1;
END_PM
close $sfh;

# Helper: write a subprocess test script to a tempfile, run it, return output.
sub run_subprocess($code) {
    my (undef, $script_file) = tempfile(SUFFIX => '.pl', UNLINK => 1, DIR => $tmpdir);
    open my $fh, '>:utf8', $script_file or die "Cannot write $script_file: $!";
    print $fh $code;
    close $fh;
    my $out = `$perl $script_file 2>&1`;
    return ($out, $? >> 8);
}

# -------------------------------------------------------------------------
# Part 1: Behavioral equivalence
# Load C Boolean in subprocess and exercise all semiring operations.
# -------------------------------------------------------------------------

my $lib_line    = "use lib '$tmpdir/blib/arch';";
my $lib_line2   = "use lib '$tmpdir/blib/lib';";
my $lib_project = "use lib '$repo_root/lib';";
my $chalk_load  = "require DynaLoader; "
    . "DynaLoader::dl_load_file('$chalk_so', 0x01) "
    . "or die 'chalk.so: ' . DynaLoader::dl_error();";

my ($out1, $exit1) = run_subprocess(<<"END_SCRIPT");
use 5.42.0;
use utf8;
$lib_line
$lib_line2
$lib_project
$chalk_load
require Chalk::Bootstrap::Semiring::Boolean;

my \$b = Chalk::Bootstrap::Semiring::Boolean->new();

# zero / one
my \$zero = \$b->zero();
my \$one  = \$b->one();
print defined(\$zero) ? 'ZERO_EXISTS\\n'  : 'ZERO_MISSING\\n';
print defined(\$one)  ? 'ONE_EXISTS\\n'   : 'ONE_MISSING\\n';

# is_zero
print \$b->is_zero(\$zero)  ? 'IS_ZERO_OF_ZERO_OK\\n'    : 'IS_ZERO_OF_ZERO_FAIL\\n';
print !\$b->is_zero(\$one)  ? 'IS_ZERO_OF_ONE_OK\\n'     : 'IS_ZERO_OF_ONE_FAIL\\n';
print !\$b->is_zero(1)     ? 'IS_ZERO_OF_INT_ONE_OK\\n' : 'IS_ZERO_OF_INT_ONE_FAIL\\n';

# multiply: zero * anything = zero; one * one = one
my \$r1 = \$b->multiply(\$zero, \$one);
print \$b->is_zero(\$r1)  ? 'MULT_ZERO_ONE_OK\\n'  : 'MULT_ZERO_ONE_FAIL\\n';

my \$r2 = \$b->multiply(\$one, \$zero);
print \$b->is_zero(\$r2)  ? 'MULT_ONE_ZERO_OK\\n'  : 'MULT_ONE_ZERO_FAIL\\n';

my \$r3 = \$b->multiply(\$one, \$one);
print !\$b->is_zero(\$r3) ? 'MULT_ONE_ONE_OK\\n'   : 'MULT_ONE_ONE_FAIL\\n';

# add: zero + zero = zero; zero + one = one; one + zero = one
my \$a1 = \$b->add(\$zero, \$zero);
print \$b->is_zero(\$a1)  ? 'ADD_ZERO_ZERO_OK\\n'  : 'ADD_ZERO_ZERO_FAIL\\n';

my \$a2 = \$b->add(\$zero, \$one);
print !\$b->is_zero(\$a2) ? 'ADD_ZERO_ONE_OK\\n'   : 'ADD_ZERO_ONE_FAIL\\n';

my \$a3 = \$b->add(\$one, \$zero);
print !\$b->is_zero(\$a3) ? 'ADD_ONE_ZERO_OK\\n'   : 'ADD_ONE_ZERO_FAIL\\n';

# on_scan: multiply(value, one)
my \$scanned = \$b->on_scan(\$one, 'TestRule', 0, 0, 'a');
print !\$b->is_zero(\$scanned) ? 'ON_SCAN_OK\\n'      : 'ON_SCAN_FAIL\\n';

# on_complete: identity — returns value unchanged
my \$completed = \$b->on_complete(\$one, 'TestRule', 0, 0, 0);
print !\$b->is_zero(\$completed) ? 'ON_COMPLETE_OK\\n' : 'ON_COMPLETE_FAIL\\n';

# should_scan: always returns true for Boolean
print \$b->should_scan(\$one, 'TestRule', 0, 0, '', {}) ? 'SHOULD_SCAN_OK\\n' : 'SHOULD_SCAN_FAIL\\n';

# supports_leo: Boolean supports Leo optimization
print \$b->supports_leo() ? 'SUPPORTS_LEO_OK\\n' : 'SUPPORTS_LEO_FAIL\\n';

print 'EQUIV_OK\\n';
END_SCRIPT

is($exit1, 0, 'Part 1 subprocess exits cleanly')
    or diag("Part 1 output:\n$out1");

like($out1, qr/ZERO_EXISTS/,          'Part 1: zero() returns defined value');
like($out1, qr/ONE_EXISTS/,           'Part 1: one() returns defined value');
like($out1, qr/IS_ZERO_OF_ZERO_OK/,   'Part 1: is_zero(zero) is true');
like($out1, qr/IS_ZERO_OF_ONE_OK/,    'Part 1: is_zero(one) is false');
like($out1, qr/IS_ZERO_OF_INT_ONE_OK/,'Part 1: is_zero(1) is false');
like($out1, qr/MULT_ZERO_ONE_OK/,     'Part 1: multiply(zero, one) = zero');
like($out1, qr/MULT_ONE_ZERO_OK/,     'Part 1: multiply(one, zero) = zero');
like($out1, qr/MULT_ONE_ONE_OK/,      'Part 1: multiply(one, one) = one');
like($out1, qr/ADD_ZERO_ZERO_OK/,     'Part 1: add(zero, zero) = zero');
like($out1, qr/ADD_ZERO_ONE_OK/,      'Part 1: add(zero, one) = one');
like($out1, qr/ADD_ONE_ZERO_OK/,      'Part 1: add(one, zero) = one');
like($out1, qr/ON_SCAN_OK/,           'Part 1: on_scan returns non-zero');
like($out1, qr/ON_COMPLETE_OK/,       'Part 1: on_complete returns value unchanged');
like($out1, qr/SHOULD_SCAN_OK/,       'Part 1: should_scan always returns true');
like($out1, qr/SUPPORTS_LEO_OK/,      'Part 1: supports_leo returns true');
like($out1, qr/EQUIV_OK/,             'Part 1: all semiring operations verified');

# -------------------------------------------------------------------------
# Part 2: Earley parser integration
# Load C Boolean + Earley in subprocess, parse with a simple grammar.
# -------------------------------------------------------------------------

my ($out2, $exit2) = run_subprocess(<<"END_SCRIPT");
use 5.42.0;
use utf8;
$lib_line
$lib_line2
$lib_project
$chalk_load
require Chalk::Bootstrap::Semiring::Boolean;

# Load grammar and parser classes (pure Perl)
require Chalk::Grammar::Symbol;
require Chalk::Grammar::Rule;
require Chalk::Bootstrap::Earley;

# Build a simple grammar: Start -> 'a'
my \$grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Start',
        expressions => [[
            Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a'),
        ]],
    ),
];

my \$semiring = Chalk::Bootstrap::Semiring::Boolean->new();
my \$parser   = Chalk::Bootstrap::Earley->new(
    grammar  => \$grammar,
    semiring => \$semiring,
);

# "a" must be accepted
print \$parser->parse('a')  ? 'PARSE_A_OK\\n'     : 'PARSE_A_FAIL\\n';

# "b" must be rejected
print !\$parser->parse('b') ? 'REJECT_B_OK\\n'    : 'REJECT_B_FAIL\\n';

# empty string must be rejected
print !\$parser->parse('')  ? 'REJECT_EMPTY_OK\\n' : 'REJECT_EMPTY_FAIL\\n';

# "aa" (two chars) must be rejected
print !\$parser->parse('aa') ? 'REJECT_AA_OK\\n'  : 'REJECT_AA_FAIL\\n';

print 'EARLEY_OK\\n';
END_SCRIPT

is($exit2, 0, 'Part 2 subprocess exits cleanly')
    or diag("Part 2 output:\n$out2");

like($out2, qr/PARSE_A_OK/,      'Part 2: Earley+C Boolean accepts "a"');
like($out2, qr/REJECT_B_OK/,     'Part 2: Earley+C Boolean rejects "b"');
like($out2, qr/REJECT_EMPTY_OK/, 'Part 2: Earley+C Boolean rejects empty string');
like($out2, qr/REJECT_AA_OK/,    'Part 2: Earley+C Boolean rejects "aa"');
like($out2, qr/EARLEY_OK/,       'Part 2: Earley parser integration complete');

done_testing;
