# ABOUTME: Grammar gaps that kept lib/Chalk/*.pm out of perl-recognize-phase5.t:
# ABOUTME: punctuation variables and package-qualified aggregates.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
unless (defined $ir) {
    plan skip_all => 'Perl grammar failed to parse';
    exit;
}
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new()->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase5Gaps/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated grammar code failed: $@";
    exit;
}
my $grammar    = Chalk::Grammar::Perl::Phase5Gaps::grammar();
my $recognizer = build_perl_recognizer($grammar, start => 'Program');
my $parser     = build_perl_ir_parser($grammar, start => 'Program');

# The Boolean recognizer is what perl-recognize-phase5.t runs; the full
# five-semiring parser must also come out with exactly one parse (it dies on
# an ambiguity the filters leave) and build IR.
my sub ir_of($src) {
    $parser->semiring->reset_cache();
    my $ctx = $parser->parse_value($src);
    return undef if !defined $ctx || $ctx->is_zero();
    return $ctx->extract();
}

my sub accepts($src, $label) {
    subtest $label => sub {
        ok($recognizer->parse($src), "recognized: $src");
        my $ir = eval { ir_of($src) };
        is($@, '', 'the full pipeline does not die');
        ok(defined $ir, "parsed to IR: $src");
    };
}

my sub rejects($src, $label) {
    ok(!$recognizer->parse($src), $label);
}


# ============================================================================
# §1 Punctuation variables. perl -c accepts each in an expression position;
# `$,`, `$;` and `$$` are left out: they collide with the signature
# placeholder (`($,)`), the statement terminator and `$$ref`.
# ============================================================================

accepts('my $e = $@;',                      '$@ (eval error)');
accepts('die $@ if $@;',                    '$@ as a postfix-if condition');
accepts('my $m = $@ =~ s/\n.*//sr;',        '$@ bound to a substitution');
accepts('my $e = $!;',                      '$! (errno)');
accepts('open(my $fh, "<", $f) or die "$f: $!";', '$! inside a string stays opaque');
accepts('die $!;',                          '$! as a call argument');
accepts('local $/;',                        '$/ (input record separator)');
accepts('local $\ = "\n";',                 '$\\ (output record separator)');
accepts('my $n = $.;',                      '$. (input line number)');
accepts('my $w = $&;',                      '$& (last match)');
accepts('my $o = $^O;',                     '$^O (control-character name)');
accepts('local $^W = 0;',                   '$^W assigned');
accepts('my $b = ${^WARNING_BITS};',        '${^NAME} (caret-brace name)');
accepts('my $z = $0;',                      '$0 (program name, a digit variable)');
rejects('my $e = $@@;',                     'rejects $@@');

# ============================================================================
# §2 Package-qualified aggregates (and `$::x`, the main-package short form).
# ============================================================================

accepts('my @a = @Pkg::x;',                 '@Pkg::x');
accepts('my %h = %Pkg::x;',                 '%Pkg::x');
accepts('my $s = $Pkg::x;',                 '$Pkg::x (pre-existing)');
accepts('my @a = @Pkg::Sub::x;',            '@Pkg::Sub::x');
accepts('my @a = @::x;',                    '@::x');
accepts('my %h = %::x;',                    '%::x');
accepts('my $s = $::x;',                    '$::x');
accepts('our @ISA = @Foo::ISA;',            'our @ISA = @Foo::ISA');
accepts('my $n = scalar @Pkg::x;',          'scalar of a qualified array');
accepts('my $v = $Pkg::x{a};',              'element of a qualified hash');
rejects('my @a = @Pkg::;',                  'rejects @Pkg:: (a stash name: out of the subset, spec section 2)');
rejects('my @a = @::;',                     'rejects @:: (the main stash)');

done_testing();
