my $s = "a"; $s = "b" . $s; $s = sprintf("%s%s", $s, $s); print "$s\n";
