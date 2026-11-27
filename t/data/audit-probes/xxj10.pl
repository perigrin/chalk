my $s = "aaa"; $s =~ /a/g; my $p = pos($s); $s =~ /a/g; print $p, pos($s), "\n";
