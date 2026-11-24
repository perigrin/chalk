our $g=1; for my $i (1..3) { local $g=$i; last if $i==2 } print "$g\n";
