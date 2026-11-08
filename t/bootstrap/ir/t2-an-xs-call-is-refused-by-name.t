# ABOUTME: a call to an XS sub (B::SoN marks it xs) has no Perl source to compile, so T2
# ABOUTME: refuses it by that name -- not as a call with no sub. PadWalker is one such.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;
require Chalk::Target::LLVM::T2;

# T2's own reason, read where lower_program gives up.
my $why;
{
    no warnings 'redefine';
    my $orig = \&Chalk::Target::LLVM::T2::lower_program;
    *Chalk::Target::LLVM::T2::lower_program = sub { my $r = $orig->(@_); $why = $r ? 'taken' : ( $@ =~ s/\n.*//sr ); $r };
}

my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
print $fh qq{use List::Util qw(sum);\nmy \$i = \$ENV{X} // 2;\nprint sum(\$i, 1), "\\n";\n};
close $fh;
my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
like($why, qr/main::sum is XS/, 'T2 refuses the XS call by name');
done_testing;
