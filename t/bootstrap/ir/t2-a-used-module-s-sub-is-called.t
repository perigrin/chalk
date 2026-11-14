# ABOUTME: a sub from a module the program `use`s is compiled with it (B::SoN follows
# ABOUTME: use/require) and called through T2 -- by its full name, or by an imported one.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

my $dir = tempdir( CLEANUP => 1 );
mkdir "$dir/lib" or die $!;
sub write_file ( $path, $src ) { open my $fh, '>', $path or die "$path: $!"; print {$fh} $src; close $fh }
write_file( "$dir/lib/UrMod.pm", "package UrMod;\nsub f { return \$_[0] * 2 }\n1;\n" );
write_file( "$dir/lib/UrExp.pm",
    "package UrExp;\nuse Exporter 'import';\nour \@EXPORT_OK = qw(g);\nsub g { return \$_[0] + 1 }\n1;\n" );

for my $case (
    [ "use lib '$dir/lib';\nuse UrMod;\nprint UrMod::f(21), \"\\n\";\n", 'a used module\'s sub, by its full name' ],
    [ "use lib '$dir/lib';\nuse UrExp qw(g);\nprint g(41), \"\\n\";\n",   'an imported sub, by its imported name' ],
) {
    my ( $src, $name ) = @$case;
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    local $Chalk::Target::LLVM::Lower::PATH;
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail( $json,
        sub ($g, $m) { my $x = $g->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $x->returns->[0] ]) },
        program_mode => 1 );
    my $u = $units->[0] // {};
    is( $u->{path} // '', 't2', "$name: lowered through T2" ) or diag $err // $u->{err} // $u->{path_why};
    next unless $u->{ok};
    my ( $lf, $ll ) = tempfile( SUFFIX => '.ll', UNLINK => 1 );
    print $lf $u->{ll}; close $lf;
    is( scalar qx(timeout 20 $LLI $ll 2>&1), scalar qx($^X $pl 2>&1), "$name: perl's answer" );
}

done_testing;
