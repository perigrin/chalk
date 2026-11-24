our $g=1; sub in { local $g=$g+1; die "x\n" if $g>3; in() } eval { in() }; print "$g\n";
