my $s = "abcd"; $s =~ /b/g; my $t = $s; print defined pos($t) ? "d" : "u", pos($s), "\n";
