my @l=(1,2,3); my $rm=sub { shift @l }; my $t=0; while (@l) { $t+=$l[0]; $rm->() } print "$t\n";
