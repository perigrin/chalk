sub f { $_[0]++ } my $t = 0; for (my $i = 0; $i < 3; $i++) { f($i); $t += $i } print "$t\n";
