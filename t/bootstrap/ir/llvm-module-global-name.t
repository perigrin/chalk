# ABOUTME: Teeth for _module_global_name — the shared owner of the LLVM
# ABOUTME: string-global prefix + byte-length, incl. the illegal-identifier die.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::Target::LLVM::Context;

sub mk_ctx { Chalk::Target::LLVM::Context->new }

subtest 'byte length, not char length, for a UTF-8-flagged string' => sub {
    my $ctx = mk_ctx();
    # A UTF-8-flagged multibyte string: "é" (U+00E9) is 1 char but 2 bytes once
    # the UTF-8 flag is on. The [N x i8] size must be the encoded byte count
    # (+1 for NUL) or the global array is undersized. Plain length() would give
    # the char count (1) — the CHAR-vs-BYTE divergence this helper closes.
    my $s = "\x{e9}";
    utf8::upgrade($s);                       # force the UTF-8 internal form
    is(length($s), 1, 'char length is 1');
    my ($gname, $blen, $total) = $ctx->_module_global_name('str_const', $s);
    is($blen,  2, 'byte length of "é" is 2 (UTF-8 encoded)');
    is($total, 3, 'array size = byte length + 1 for NUL');
    is($gname, '@str_const_0', 'name at module scope, index 0');
    # The registered global carries the same byte length.
    my $g = $ctx->{_str_globals}[0];
    is($g->[2], 2, 'registered _str_globals entry uses byte length');
};

subtest 'sequential globals get sequential indices' => sub {
    my $ctx = mk_ctx();
    my ($a) = $ctx->_module_global_name('str_const', 'x');
    my ($b) = $ctx->_module_global_name('rxs_lit',   'y');
    my ($c) = $ctx->_module_global_name('env_key',   'z');
    is($a, '@str_const_0', 'first global index 0');
    is($b, '@rxs_lit_1',   'second global index 1 (shared counter)');
    is($c, '@env_key_2',   'third global index 2');
};

subtest 'method-body prefix keeps globals unique across bodies' => sub {
    my $ctx = mk_ctx();
    $ctx->{_in_method_body}    = 1;
    $ctx->{_method_class_name} = 'Point';
    $ctx->{_method_name}       = 'greet';
    my ($gname) = $ctx->_module_global_name('str_const', 'hi');
    is($gname, '@Point__greet__str_const_0',
        'method-body global is prefixed by class__method');
};

subtest 'illegal identifier (class name with ::) dies loudly (G6 S4)' => sub {
    my $ctx = mk_ctx();
    $ctx->{_in_method_body}    = 1;
    $ctx->{_method_class_name} = 'Foo::Bar';   # :: is not a legal LLVM identifier
    $ctx->{_method_name}       = 'm';
    my $err = eval { $ctx->_module_global_name('str_const', 'x'); 1 };
    ok(!$err, 'a class name with :: does not silently produce an illegal global');
    like($@, qr/not a legal unquoted identifier/,
        'the die names the illegal-identifier cause');
    # And nothing was registered — the die happens before the push.
    is(scalar $ctx->{_str_globals}->@*, 0, 'no global registered on the failed call');
};

done_testing;
