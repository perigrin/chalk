my @a = (1,2,3); my $c = sub { $a[2] = 0 }; my $s = ""; for my $e (@a) { $c->(); $s .= $e } print "$s\n";
