my $s = "aab"; $s =~ /a/g; $s = "aab"; print defined pos($s) ? "d" : "u"; $s =~ /a/g; pos($s) = 0; $s =~ /(a+)/g; print "$1\n";
