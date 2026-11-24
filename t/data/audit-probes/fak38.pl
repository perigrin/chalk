my $done=0; my $stop=sub { $done=1 }; my $n=0; until ($done) { $n++; $stop->() if $n==3 } print "$n\n";
