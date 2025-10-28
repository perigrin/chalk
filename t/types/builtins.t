# ABOUTME: Tests for built-in function type signatures
# ABOUTME: Validates that Chalk::Builtins provides correct type information

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Builtins;
use Chalk::Type::Int;
use Chalk::Type::Str;
use Chalk::Type::Boolean;
use Chalk::Type::Array;
use Chalk::Type::List;

subtest 'Builtins has signature for common functions' => sub {
    my $builtins = Chalk::Builtins->new();

    ok($builtins->has_signature('length'), 'Has length signature');
    ok($builtins->has_signature('push'), 'Has push signature');
    ok($builtins->has_signature('defined'), 'Has defined signature');
    ok($builtins->has_signature('keys'), 'Has keys signature');
    ok($builtins->has_signature('join'), 'Has join signature');
};

subtest 'String function signatures' => sub {
    my $builtins = Chalk::Builtins->new();

    my $length_sig = $builtins->get_signature('length');
    ok(defined($length_sig), 'length has signature');
    isa_ok($length_sig->{params}[0], 'Chalk::Type::Str',
           'length takes Str param');
    isa_ok($length_sig->{returns}, 'Chalk::Type::Int',
           'length returns Int');

    my $uc_sig = $builtins->get_signature('uc');
    isa_ok($uc_sig->{params}[0], 'Chalk::Type::Str',
           'uc takes Str param');
    isa_ok($uc_sig->{returns}, 'Chalk::Type::Str',
           'uc returns Str');
};

subtest 'Array function signatures' => sub {
    my $builtins = Chalk::Builtins->new();

    my $push_sig = $builtins->get_signature('push');
    ok(defined($push_sig), 'push has signature');
    isa_ok($push_sig->{params}[0], 'Chalk::Type::Array',
           'push takes Array param');
    isa_ok($push_sig->{returns}, 'Chalk::Type::Int',
           'push returns Int');

    my $pop_sig = $builtins->get_signature('pop');
    isa_ok($pop_sig->{params}[0], 'Chalk::Type::Array',
           'pop takes Array param');
    isa_ok($pop_sig->{returns}, 'Chalk::Type::Scalar',
           'pop returns Scalar');
};

subtest 'Type checking function signatures' => sub {
    my $builtins = Chalk::Builtins->new();

    my $defined_sig = $builtins->get_signature('defined');
    ok(defined($defined_sig), 'defined has signature');
    isa_ok($defined_sig->{params}[0], 'Chalk::Type::Any',
           'defined takes Any param');
    isa_ok($defined_sig->{returns}, 'Chalk::Type::Boolean',
           'defined returns Boolean');
};

subtest 'List all functions' => sub {
    my $builtins = Chalk::Builtins->new();

    my @functions = $builtins->all_functions();
    ok(scalar(@functions) > 0, 'Returns list of functions');
    ok((grep { $_ eq 'length' } @functions), 'Includes length');
    ok((grep { $_ eq 'push' } @functions), 'Includes push');
    ok((grep { $_ eq 'defined' } @functions), 'Includes defined');
};

done_testing();
