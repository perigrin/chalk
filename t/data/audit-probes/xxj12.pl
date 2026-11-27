my $s = "aaa"; $s =~ /a/g; $s = "bbb"; print defined pos($s) ? "d" : "u", "\n";
