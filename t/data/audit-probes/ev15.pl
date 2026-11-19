my $c = 0; my @l = (1,2,3); for my $v (@l) { eval { die "s\n" if $v == 2; $c += $v; 1 } or $c += 100 } print "$c\n";
