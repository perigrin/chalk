our $g=1; for my $i (1..2) { eval { local $g=$g+$i; die "x\n" if $i==1; print $g } } print "$g\n";
