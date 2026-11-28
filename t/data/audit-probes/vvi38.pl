my $s = "abc"; substr($s, 0, 2) =~ tr/a-b/A-B/; print "$s\n";
