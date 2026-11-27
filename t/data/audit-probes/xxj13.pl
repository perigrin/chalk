my $s = "aaa"; $s =~ /a/g; my $t = $s; $t =~ /a/g; print pos($s), pos($t), "\n";
