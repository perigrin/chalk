# ABOUTME: A CallExpression's argument collectors read the call's OWN arguments:
# ABOUTME: `push(@a, 1)` reaches the signature check as (Array, Int), arity 2.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::TypeInference;

# The builtin signature check in TypeInference reads a call's argument count
# (_get_list_arity) and argument types (_get_item_types) off the shared parse
# tree. Those walks stop at completed sub-expressions so that an inner call's
# arguments never stand in for the outer call's. A walk that also stops at
# the PARTIAL items between an ExpressionList and its left operand loses
# every argument but the last: `push(@a, 1)` arrived as (Int), and the check
# refused a valid call for want of push's Array.

my $ir = perl_pipeline();
die 'Perl grammar failed', "\n" unless defined $ir;
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CallArgsTest/g;
eval $generated;
die "Generated grammar failed: $@", "\n" if $@;
my $parser = build_perl_ir_parser(
    Chalk::Grammar::Perl::CallArgsTest::grammar(), start => 'Program');

# What the CallExpression completions of the named call saw: one record per
# completion, [arity, [item types]]. Observed from the semiring's own
# collectors, at the point the signature check calls them.
my ( $watch, @seen );
{
    no warnings 'redefine';
    my $orig = \&Chalk::Bootstrap::Semiring::TypeInference::_complete_type;
    *Chalk::Bootstrap::Semiring::TypeInference::_complete_type = sub {
        my ( $self, $value, $rule, $alt ) = @_;
        if ( $rule eq 'CallExpression' && ( $self->_get_head_ident($value) // '' ) eq $watch ) {
            push @seen, [
                $self->_get_list_arity($value),
                [ map { $_ // 'undef' } ( $self->_get_item_types($value) // [] )->@* ],
            ];
        }
        return $orig->(@_);
    };
}

sub args_of ( $name, $src ) {
    ( $watch, @seen ) = ($name);
    $parser->semiring->reset_cache;
    $parser->parse_value($src);
    return @seen;
}

sub saw ( $name, $src, $arity, $types ) {
    my @seen = args_of( $name, $src );
    ok( ( grep { ( $_->[0] // -1 ) == $arity && "@{ $_->[1] }" eq "@$types" } @seen ),
        "$src: $name sees ($arity: @$types)" )
        or diag explain \@seen;
}

saw( 'push', 'my @a; push(@a, 1);',      2, [qw(Array Int)] );
saw( 'push', 'my @a; push @a, 1;',       2, [qw(Array Int)] );
saw( 'join', 'my @a; join(",", @a);',    2, [qw(Str Array)] );
saw( 'push', 'my @a; push(@a, 1, "x");', 3, [qw(Array Int Str)] );

# An inner call's arguments stay the inner call's: the outer push sees two
# arguments, the second being the inner call, never f's (1, 2, 3).
{
    my @seen = args_of( 'push', 'my @a; push(@a, f(1, 2, 3));' );
    ok( ( grep { ( $_->[0] // -1 ) == 2 && @{ $_->[1] } == 2 && $_->[1][0] eq 'Array' } @seen ),
        'push(@a, f(1, 2, 3)): push sees its own two arguments' )
        or diag explain \@seen;
    ok( !( grep { ( $_->[0] // 0 ) > 2 } @seen ),
        '... never the inner call\'s three' )
        or diag explain \@seen;
}

done_testing;
