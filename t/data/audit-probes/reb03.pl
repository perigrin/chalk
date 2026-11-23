our $g=1; for my $i (1..2) { eval { local $g=$i+5; die "d\n" if $i==1; }; print "$g\n" }
