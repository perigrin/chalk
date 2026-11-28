my $s = "abc"; my $i = index($s, "c"); $s = "c" . $s; my $j = index($s, "c"); print "$i$j\n";
