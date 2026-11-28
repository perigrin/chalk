my $s = "abc"; my $t = "$s" . chop($s) . "$s"; print "$t\n";
