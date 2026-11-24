my @d=(1,0); my $t=0; for my $d (@d) { $t += 1; last unless $d; $t += 4/$d } print "$t\n";
