my $s = "abcd"; $s =~ /b/g; my $p = pos($s); $s =~ /./g; print $p, pos($s), "\n";
