our $g=1; eval { for my $i (1..3) { local $g=$i; die "x\n" if $i==2 } }; print "$g\n";
