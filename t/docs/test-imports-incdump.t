# ABOUTME: tools/test-imports/INCdump.pm credits a require to the module that asked for it:
# ABOUTME: a `use parent` load is the child module's, not parent.pm's.
use 5.42.0;
use lib 't/lib';
use Test::Chalk;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);
sub put ($name, $body) { open my $fh, '>', "$dir/$name" or die "$name: $!"; print $fh $body; close $fh }
put('IDBase.pm', "package IDBase; sub hi { 1 } 1;\n");
put('IDKid.pm',  "package IDKid; use parent 'IDBase'; 1;\n");
put('IDOld.pm',  "package IDOld; use base 'IDBase'; 1;\n");

sub edges_for ($module) {
    my $out = "$dir/$module.inc";
    unlink $out;
    local $ENV{INCDUMP_OUT} = $out;
    system($^X, "-I$dir", '-Itools/test-imports', '-MINCdump', "-M$module", '-e', '1') == 0
        or die "perl -M$module failed";
    open my $fh, '<', $out or die "$out: $!";
    return [ grep { /\A[RE]\tIDBase\.pm\t/ } <$fh> ];
}

my $kid = edges_for('IDKid');
is( scalar @$kid, 1, 'use parent: one require edge for the base class' );
like( $kid->[0] // '', qr{\A[RE]\tIDBase\.pm\t\Q$dir\E/IDKid\.pm\t}, 'use parent: credited to IDKid.pm, not parent.pm' );

my $old = edges_for('IDOld');
like( $old->[0] // '', qr{\A[RE]\tIDBase\.pm\t\Q$dir\E/IDOld\.pm\t}, 'use base: credited to IDOld.pm, not base.pm' );

done_testing;
