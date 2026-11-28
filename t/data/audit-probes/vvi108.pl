my $s = "abcd"; $s =~ /b/g; $s .= "e"; print defined pos($s) ? "d" : "u", "\n";
