my $s = "aab"; $s =~ /a/g; $s =~ /z/gc; my $k = pos($s); $s =~ /z/g; print $k, defined pos($s) ? "d" : "u", "\n";
