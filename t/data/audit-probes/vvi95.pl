my $s = "abc"; $s =~ /(b)/; for my $w ("x", "y") { $w =~ /(.)/; } print $1, "\n";
