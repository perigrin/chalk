my @a = (1,2,3); my $t = 0; for my $e (@a) { $t += $e; $a[-1] = 10 } print "$t\n";
