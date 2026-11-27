my $s = "ab"; my $n = ($s =~ tr/a/x/); my $t = reverse $s; my $j = join "-", $s, $n; print "$t$j\n";
