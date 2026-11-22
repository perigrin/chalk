our $g=0; sub bump { $g += 10 } my $i=0; do { $g = $g+1; bump(); $i++ } until $i>=3; print "$g\n";
