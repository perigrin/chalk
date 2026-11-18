# INCdump -- measurement aid for tools/test-imports. Load with -MINCdump.
# Records every first-time require (who required it, from where, in which phase),
# then %INC at INIT (compile time) and at END (adds run-time requires), plus
# DynaLoader's list of modules whose shared object was loaded.
# Deliberately uses no modules, so it adds nothing to %INC but itself.
package INCdump;
our $PID = $$;
our $OUT = $ENV{INCDUMP_OUT};
our @REQ;
our $INIT_DONE = 0;

${^HOOK}{require__before} = sub {
    my $name = $_[0];
    return if ref $name;
    # (a `use parent`/`use base` load is the module's that said it, not parent.pm's)
    my $i = 0;
    my @c = caller($i);
    @c = caller(++$i) while @c && ( $c[1] // '' ) =~ m{(?:\A|/)(?:parent|base)\.pm\z} && caller($i + 1);
    # R = first load of this file; E = a later require of an already-loaded file
    push @REQ, join "\t", ( exists $INC{$name} ? 'E' : 'R' ), $name, ( $c[1] // '?' ), ( $c[2] // '?' ), ${^GLOBAL_PHASE};
    return;
};

sub _write {
    my ($tag) = @_;
    return unless defined $OUT && $$ == $PID;
    open my $fh, '>>', $OUT or return;
    print $fh "$_\n" for @REQ;
    @REQ = ();
    for my $k ( sort keys %INC ) {
        next if $k eq 'INCdump.pm';
        my $v = $INC{$k};
        $v = ref($v) ? 'REF:' . ref($v) : defined($v) ? $v : 'UNDEF';
        print $fh join( "\t", $tag, $k, $v ), "\n";
    }
    print $fh join( "\t", "${tag}_DL", $_ ), "\n" for @DynaLoader::dl_modules;
    print $fh "${tag}_DONE\n";
    close $fh;
}

INIT { $INIT_DONE = 1; _write('INIT') }
END  { _write('END') }

1;
