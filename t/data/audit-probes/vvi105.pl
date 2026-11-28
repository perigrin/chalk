my $s = "abc"; pos($s) = 1; $s =~ /\G(.)/g; print $1, pos($s), "\n";
