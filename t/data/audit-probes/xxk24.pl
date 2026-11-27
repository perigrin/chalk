my $s = "abc"; for my $v ($s) { $v =~ s/a/A/; $v =~ tr/b/B/; } print "$s\n";
