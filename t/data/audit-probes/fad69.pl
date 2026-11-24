our $g=1; sub f { local $g=2; my $n = $_[0] ** 0.5; sqrt($_[0]) } eval { f(-1) }; print "$g ", $@?1:0, "\n";
