my $s = "abcdef"; my $t = substr($s, 2, 2) . substr($s, 0, 2, ""); print "$s$t\n";
