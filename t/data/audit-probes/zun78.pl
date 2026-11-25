our $g=1; eval { my $i=0; while (1) { local $g=++$i; die "x\n" if $i==3 } }; print "$g\n";
